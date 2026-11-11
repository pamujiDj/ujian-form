import Foundation

/// Semua pengaturan penting ada di sini. Ubah sesuai kebutuhan sekolah.
enum Config {
    static let appVersion = "1.1"

    /// Alamat website ujian.
    static let examURL = "https://sas.smpnegeri45sby.sch.id"

    /// Domain yang boleh dibuka. Link ke domain lain diblokir.
    static let allowedHosts = ["sas.smpnegeri45sby.sch.id"]

    /// PIN pengawas untuk membuka kunci / keluar dari ujian. GANTI SEBELUM DIPAKAI!
    static let proctorPin = "450945"

    /// KUNCI RAHASIA tanda pengenal aplikasi ke server. Harus SAMA dengan ILOK_SECRET di server/ilok_guard.php
    /// dan Config.SECRET di aplikasi Android. GANTI dengan teks acak panjang!
    static let secret = "GANTI_DENGAN_KUNCI_RAHASIA_ANDA_123"

    /// Lama berlaku satu token (detik). Harus sama dengan ILOK_WINDOW di server.
    static let tokenWindowSec = 600

    /// Jumlah pelanggaran sebelum ujian dikunci.
    static let maxViolations = 3

    /// Tolak perangkat jailbreak.
    static let blockJailbreak = true

    /// Wajibkan Guided Access (Akses Terpandu) aktif sebelum ujian dimulai.
    static let requireGuidedAccess = false
}
