import UIKit
import CryptoKit

/// Tanda pengenal ke server + deteksi jailbreak.
enum Security {

    /// ID perangkat singkat (8 hex) dari identifierForVendor yang di-hash.
    static let deviceId: String = {
        let id = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let digest = SHA256.hash(data: Data(id.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(8))
    }()

    /// User-Agent = UA asli + " ILOK/1.1 t=<jendela waktu> k=<HMAC> d=<id perangkat> v=<pelanggaran>".
    /// Server memverifikasi k = HMAC-SHA256(SECRET, t + "|" + d)[0..16] (sama dengan versi Android).
    static func userAgent(base: String, violations: Int) -> String {
        let t = Int(Date().timeIntervalSince1970) / Config.tokenWindowSec
        let d = deviceId
        let key = SymmetricKey(data: Data(Config.secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(t)|\(d)".utf8), using: key)
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        let k = String(hex.prefix(16))
        return "\(base) ILOK/\(Config.appVersion) t=\(t) k=\(k) d=\(d) v=\(violations)"
    }

    /// Pemeriksaan jailbreak dasar.
    static var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let paths = [
            "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib", "/bin/bash", "/usr/sbin/sshd",
            "/etc/apt", "/private/var/lib/apt/", "/usr/bin/ssh", "/var/jb", "/private/var/stash"
        ]
        for p in paths where FileManager.default.fileExists(atPath: p) { return true }
        let testPath = "/private/ilok_jb_test.txt"
        do {
            try "x".write(toFile: testPath, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
        #endif
    }
}
