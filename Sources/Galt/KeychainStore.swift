import Foundation
import CryptoKit
import IOKit

/// API Key 等机密的本机存储。
///
/// **不使用系统钥匙串**：自签名 app 的钥匙串访问受 ACL + partition list 控制，而自签名没有
/// 稳定 team id，分区会绑到 cdhash —— 每次重新打包都变，导致反复弹「允许访问密钥」授权窗。
///
/// 改为：app 私有目录下单个 **AES-GCM 加密文件**（整表加密），密钥由本机硬件标识派生。
/// 效果：永不弹窗、跨重打包稳定；加密文件只能在同一台 Mac 上解开（优于明文，弱于钥匙串）。
///
/// 类型名沿用 `KeychainStore` 以免改动调用方；实现已与系统钥匙串无关。
enum KeychainStore {
    private static let fileName = "secrets.dat"
    private static let lock = NSLock()

    static func get(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        let value = load()[account]
        return (value?.isEmpty == false) ? value : nil
    }

    static func set(_ value: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        var dict = load()
        if value.isEmpty { dict.removeValue(forKey: account) } else { dict[account] = value }
        save(dict)
    }

    // MARK: 整表加密读写

    private static var fileURL: URL {
        HistoryStore.shared.directory.appendingPathComponent(fileName)
    }

    private static func load() -> [String: String] {
        guard let blob = try? Data(contentsOf: fileURL), !blob.isEmpty,
              let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: key),
              let dict = try? JSONDecoder().decode([String: String].self, from: plain)
        else { return [:] }
        return dict
    }

    private static func save(_ dict: [String: String]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let plain = try JSONEncoder().encode(dict)
            guard let blob = try AES.GCM.seal(plain, using: key).combined else { return }
            try blob.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // 写失败静默：上层读不到即视为未配置
        }
    }

    // MARK: 派生密钥（本机硬件 UUID + 固定盐 → SHA256）

    private static let key: SymmetricKey = {
        let material = hardwareUUID() + "Galt.secret.v1.com.sorcerer.galt"
        return SymmetricKey(data: SHA256.hash(data: Data(material.utf8)))
    }()

    private static func hardwareUUID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "galt-fallback-uuid" }
        defer { IOObjectRelease(service) }
        let prop = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)
        return (prop?.takeRetainedValue() as? String) ?? "galt-fallback-uuid"
    }
}
