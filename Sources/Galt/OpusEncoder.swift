import COpusShim
import Foundation

/// 把 16kHz 单声道 Float PCM 编码为 Ogg Opus（format=ogg_opus）字节，供火山 ASR 上传压缩。
/// 仅依赖 libopus；Ogg 封装在本文件内手写（见 OggOpusMuxer），产物经 ffmpeg 校验可解码。
enum OpusEncoder {
    /// 编码入口：成功返回 ogg_opus 字节，任何环节失败返回 nil（调用方回退 WAV）。
    static func encode(samples: [Float], sampleRate: Int = 16000) -> Data? {
        guard !samples.isEmpty, sampleRate == 16000 else { return nil }

        var err: Int32 = 0
        // 2049 = OPUS_APPLICATION_AUDIO：相对 VOIP 更少语音专用处理，尽量不影响 ASR 识别
        guard let enc = opus_encoder_create(Int32(sampleRate), 1, 2049, &err), err == 0 else { return nil }
        defer { opus_encoder_destroy(enc) }
        _ = galt_opus_set_bitrate(enc, 24000)

        // Ogg pre-skip 以 48kHz 计：lookahead 为输入采样率下的样本数，×3 换算到 48k
        let lookahead = Int(galt_opus_get_lookahead(enc))
        let preSkip = UInt16(clamping: lookahead * 48000 / sampleRate)

        let frameSize = sampleRate / 50          // 20ms 帧 = 320 样本 @16k
        var packets: [[UInt8]] = []
        var buf = [UInt8](repeating: 0, count: 4000)
        var idx = 0
        while idx < samples.count {
            var frame = Array(samples[idx..<min(idx + frameSize, samples.count)])
            if frame.count < frameSize {         // 末帧补零到整帧
                frame.append(contentsOf: repeatElement(0, count: frameSize - frame.count))
            }
            let n = opus_encode_float(enc, &frame, Int32(frameSize), &buf, Int32(buf.count))
            guard n > 0 else { return nil }
            packets.append(Array(buf[0..<Int(n)]))
            idx += frameSize
        }
        guard !packets.isEmpty else { return nil }
        return OggOpusMuxer.build(packets: packets, preSkip: preSkip, inputRate: UInt32(sampleRate))
    }

    /// 复用本应用 WAV（16bit/单声道）→ ogg_opus；解析失败返回 nil。
    static func encode(fromWAV wav: Data) -> Data? {
        guard wav.count > 44 else { return nil }
        let sampleRate = wav.withUnsafeBytes { raw -> Int in
            let b = raw.bindMemory(to: UInt8.self)
            return Int(b[24]) | Int(b[25]) << 8 | Int(b[26]) << 16 | Int(b[27]) << 24
        }
        guard sampleRate == 16000 else { return nil }
        let pcm = wav.subdata(in: 44..<wav.count)
        let count = pcm.count / 2
        guard count > 0 else { return nil }
        var samples = [Float](repeating: 0, count: count)
        pcm.withUnsafeBytes { raw in
            let i16 = raw.bindMemory(to: Int16.self)
            for i in 0..<count { samples[i] = Float(Int16(littleEndian: i16[i])) / 32767 }
        }
        return encode(samples: samples, sampleRate: sampleRate)
    }
}

/// 极简 Ogg 封装器，仅服务单流单声道 Opus（RFC 7845）。
/// 页结构：OpusHead(BOS) → OpusTags → 若干音频页(末页 EOS)。
enum OggOpusMuxer {
    static func build(packets: [[UInt8]], preSkip: UInt16, inputRate: UInt32) -> Data {
        let serial = UInt32.random(in: .min ... .max)
        var out: [UInt8] = []
        var seq: UInt32 = 0

        out += page(serial: serial, seq: seq, headerType: 0x02, granule: 0, packets: [opusHead(preSkip: preSkip, inputRate: inputRate)])
        seq += 1
        out += page(serial: serial, seq: seq, headerType: 0x00, granule: 0, packets: [opusTags()])
        seq += 1

        // 每页最多打包 50 个 20ms 包（≈1s）：lacing 值远低于 255 上限
        let perPage = 50
        var completed = 0
        var i = 0
        while i < packets.count {
            let chunk = Array(packets[i ..< min(i + perPage, packets.count)])
            completed += chunk.count
            let granule = Int64(completed) * 960     // 每包 20ms = 960 样本 @48k
            let isLast = (i + perPage) >= packets.count
            out += page(serial: serial, seq: seq, headerType: isLast ? 0x04 : 0x00, granule: granule, packets: chunk)
            seq += 1
            i += perPage
        }
        return Data(out)
    }

    /// OpusHead 标识头（声道映射族 0，单声道）
    private static func opusHead(preSkip: UInt16, inputRate: UInt32) -> [UInt8] {
        var h: [UInt8] = Array("OpusHead".utf8)
        h.append(1)                 // version
        h.append(1)                 // channel count
        appendLE16(&h, preSkip)     // pre-skip
        appendLE32(&h, inputRate)   // 原始输入采样率（信息性）
        appendLE16(&h, 0)           // output gain
        h.append(0)                 // channel mapping family
        return h
    }

    /// OpusTags 注释头
    private static func opusTags() -> [UInt8] {
        var t: [UInt8] = Array("OpusTags".utf8)
        let vendor = Array("galt".utf8)
        appendLE32(&t, UInt32(vendor.count)); t += vendor
        appendLE32(&t, 0)           // user comment list length
        return t
    }

    /// 组一个 Ogg 页：含 lacing 段表、CRC 回填
    private static func page(serial: UInt32, seq: UInt32, headerType: UInt8, granule: Int64, packets: [[UInt8]]) -> [UInt8] {
        var lacing: [UInt8] = []
        var payload: [UInt8] = []
        for pkt in packets {
            var len = pkt.count
            while len >= 255 { lacing.append(255); len -= 255 }
            lacing.append(UInt8(len))   // 收尾段 <255，标记包边界（整除时为 0）
            payload += pkt
        }
        precondition(lacing.count <= 255, "单页 lacing 段数超过 255")

        var p: [UInt8] = Array("OggS".utf8)
        p.append(0)                 // stream structure version
        p.append(headerType)
        var g = UInt64(bitPattern: granule)
        for _ in 0..<8 { p.append(UInt8(g & 0xff)); g >>= 8 }
        appendLE32(&p, serial)
        appendLE32(&p, seq)
        let crcIndex = p.count
        appendLE32(&p, 0)           // CRC 占位
        p.append(UInt8(lacing.count))
        p += lacing
        p += payload

        let c = crc32(p)
        p[crcIndex] = UInt8(c & 0xff)
        p[crcIndex + 1] = UInt8((c >> 8) & 0xff)
        p[crcIndex + 2] = UInt8((c >> 16) & 0xff)
        p[crcIndex + 3] = UInt8((c >> 24) & 0xff)
        return p
    }

    // MARK: - 工具

    private static func appendLE16(_ a: inout [UInt8], _ v: UInt16) {
        a.append(UInt8(v & 0xff)); a.append(UInt8((v >> 8) & 0xff))
    }

    private static func appendLE32(_ a: inout [UInt8], _ v: UInt32) {
        a.append(UInt8(v & 0xff)); a.append(UInt8((v >> 8) & 0xff))
        a.append(UInt8((v >> 16) & 0xff)); a.append(UInt8((v >> 24) & 0xff))
    }

    /// Ogg 专用 CRC32：多项式 0x04C11DB7，初值 0，无反射，无最终异或
    private static let crcTable: [UInt32] = (0..<256).map { i in
        var r = UInt32(i) << 24
        for _ in 0..<8 { r = (r & 0x8000_0000) != 0 ? (r << 1) ^ 0x04C1_1DB7 : (r << 1) }
        return r
    }

    private static func crc32(_ data: [UInt8]) -> UInt32 {
        var c: UInt32 = 0
        for b in data { c = (c << 8) ^ crcTable[Int(((c >> 24) ^ UInt32(b)) & 0xff)] }
        return c
    }
}
