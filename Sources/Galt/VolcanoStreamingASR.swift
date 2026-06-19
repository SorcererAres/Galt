import Foundation
import Compression

/// 火山引擎「流式语音识别大模型」(sauc) 适配器。
///
/// 二进制分帧协议:4 字节头 + (可选 4 字节序列号) + 4 字节负载长度 + 负载。
/// 流程:① 发「full client request」(JSON 配置) → ② 逐包发音频(PCM) → ③ 末包置负序列号收尾
/// → ④ 循环接收「full server response」累积文本,直到收到末包标志或连接结束。
///
/// 为降低实现风险,客户端发包一律**不压缩**;服务端响应若标记 gzip 则本地解压。
/// 注意:此实现按公开协议编写,需用真实账号联调后按报错微调。
enum VolcanoStreamingASR {
    // 头部字段取值
    private enum MsgType: UInt8 { case fullClient = 0b0001, audioOnly = 0b0010, fullServer = 0b1001, error = 0b1111 }
    private enum Flags: UInt8 { case posSequence = 0b0001, negWithSequence = 0b0011 }
    private enum Serialization: UInt8 { case none = 0b0000, json = 0b0001 }
    private enum Compression: UInt8 { case none = 0b0000, gzip = 0b0001 }

    static func transcribe(wav: Data, endpoint: String, resourceId: String,
                           appKey: String, accessKey: String, timeout: TimeInterval) async throws -> String {
        guard let url = URL(string: endpoint) else { throw STTError.http(-1, "火山流式接口地址无效") }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        // ① full client request：JSON 配置（不压缩）
        let config: [String: Any] = [
            "user": ["uid": "galt"],
            "audio": ["format": "pcm", "rate": 16000, "bits": 16, "channel": 1],
            "request": ["model_name": "bigmodel", "enable_itn": true, "enable_punc": true],
        ]
        let configData = try JSONSerialization.data(withJSONObject: config)
        try await task.send(.data(frame(.fullClient, .posSequence, .json, .none, sequence: 1, payload: configData)))

        // ② 逐包发送音频（PCM，去掉 WAV 头）
        let pcm = pcmPayload(fromWAV: wav)
        let chunkSize = 6_400 // 200ms @16k/16bit/mono：官方建议单包 100~200ms（200ms 性能最优）
        var seq: Int32 = 1
        var offset = 0
        if pcm.isEmpty {
            // 没有 PCM 也要发一个末包，让服务端正常收尾
            try await task.send(.data(frame(.audioOnly, .negWithSequence, .none, .none, sequence: -(seq + 1), payload: Data())))
        } else {
            while offset < pcm.count {
                let end = min(offset + chunkSize, pcm.count)
                let chunk = pcm.subdata(in: offset..<end)
                let isLast = end >= pcm.count
                seq += 1
                if isLast {
                    try await task.send(.data(frame(.audioOnly, .negWithSequence, .none, .none, sequence: -seq, payload: chunk)))
                } else {
                    try await task.send(.data(frame(.audioOnly, .posSequence, .none, .none, sequence: seq, payload: chunk)))
                }
                offset = end
            }
        }

        // ③ 接收并累积结果
        var latestText = ""
        while true {
            let message = try await task.receive()
            guard case let .data(data) = message else { continue }
            let parsed = try parseServerFrame(data)
            if let text = parsed.text, !text.isEmpty { latestText = text }
            if parsed.isError { throw STTError.http(-1, "火山流式：\(parsed.text ?? "识别失败")") }
            if parsed.isLast { break }
        }
        return latestText
    }

    // MARK: 分帧

    private static func frame(_ type: MsgType, _ flags: Flags, _ ser: Serialization, _ comp: Compression,
                              sequence: Int32?, payload: Data) -> Data {
        var d = Data()
        d.append(0x11) // protocol version=1, header size=1（即 4 字节头）
        d.append((type.rawValue << 4) | flags.rawValue)
        d.append((ser.rawValue << 4) | comp.rawValue)
        d.append(0x00) // reserved
        if let seq = sequence {
            var be = seq.bigEndian
            withUnsafeBytes(of: &be) { d.append(contentsOf: $0) }
        }
        var len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &len) { d.append(contentsOf: $0) }
        d.append(payload)
        return d
    }

    private struct ServerFrame { var text: String?; var isLast: Bool; var isError: Bool }

    private static func parseServerFrame(_ data: Data) throws -> ServerFrame {
        guard data.count >= 4 else { throw STTError.http(-1, "火山流式：响应帧过短") }
        let bytes = [UInt8](data)
        let headerSize = Int(bytes[0] & 0x0F) * 4
        let messageType = bytes[1] >> 4
        let flags = bytes[1] & 0x0F
        let compression = bytes[2] & 0x0F
        var cursor = max(headerSize, 4)
        // 含序列号(标志位最低位)：跳过 4 字节
        if flags & Flags.posSequence.rawValue != 0 { cursor += 4 }
        guard data.count >= cursor + 4 else { throw STTError.http(-1, "火山流式：响应负载缺失") }
        let payloadLen = Int(UInt32(bytes[cursor]) << 24 | UInt32(bytes[cursor + 1]) << 16
                             | UInt32(bytes[cursor + 2]) << 8 | UInt32(bytes[cursor + 3]))
        cursor += 4
        let endIndex = min(cursor + payloadLen, data.count)
        var payload = data.subdata(in: cursor..<endIndex)
        if compression == Compression.gzip.rawValue { payload = gunzip(payload) ?? payload }

        let isError = messageType == MsgType.error.rawValue
        // 末包：标志位含「负序列号」位(0b0010)即为最后一帧（兼容 NEG_SEQUENCE / NEG_WITH_SEQUENCE）
        let isLast = (flags & 0b0010) != 0 || isError

        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return ServerFrame(text: nil, isLast: isLast, isError: isError)
        }
        // 文本可能在 result.text；错误在 error/message
        var text: String?
        if let result = obj["result"] as? [String: Any], let t = result["text"] as? String { text = t }
        else if let t = obj["text"] as? String { text = t }
        if isError {
            text = (obj["error"] as? String) ?? (obj["message"] as? String) ?? text
        }
        return ServerFrame(text: text, isLast: isLast, isError: isError)
    }

    // MARK: 工具

    /// 从 WAV 容器取出裸 PCM（定位 "data" 子块；找不到则回退去掉 44 字节标准头）
    private static func pcmPayload(fromWAV wav: Data) -> Data {
        let marker: [UInt8] = Array("data".utf8)
        let bytes = [UInt8](wav)
        if bytes.count > 12 {
            var i = 12
            while i + 8 <= bytes.count {
                if Array(bytes[i..<i + 4]) == marker {
                    let dataStart = i + 8
                    return dataStart <= bytes.count ? wav.subdata(in: dataStart..<wav.count) : Data()
                }
                // 子块: id(4) + size(4) + body(size)，按 size 跳到下一个子块
                let size = Int(UInt32(bytes[i + 4]) | UInt32(bytes[i + 5]) << 8
                               | UInt32(bytes[i + 6]) << 16 | UInt32(bytes[i + 7]) << 24)
                i += 8 + size + (size & 1)
            }
        }
        return wav.count > 44 ? wav.subdata(in: 44..<wav.count) : wav
    }

    /// gzip 解压:剥掉 10 字节头与 8 字节尾,余下按 raw DEFLATE 解。
    private static func gunzip(_ data: Data) -> Data? {
        guard data.count > 18 else { return nil }
        let deflated = data.subdata(in: 10..<(data.count - 8))
        return rawInflate(deflated)
    }

    private static func rawInflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = max(data.count * 8, 64 * 1024)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { dst.deallocate() }
        let written = data.withUnsafeBytes { src -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(dst, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        return Data(bytes: dst, count: written)
    }
}
