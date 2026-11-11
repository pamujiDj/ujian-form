# ILOK untuk iOS (iPhone / iPad) — iOS 13 ke atas

Kode Swift (UIKit + WKWebView), tanpa library tambahan. Project Xcode dibuat otomatis dengan XcodeGen dari `project.yml`.

## Yang WAJIB diganti (`Sources/Config.swift`)
- `proctorPin` — PIN pengawas
- `secret` — kunci rahasia, **samakan** dengan `Config.SECRET` (Android) dan `ILOK_SECRET` (server/ilok_guard.php)

## Membuat file IPA lewat GitHub Actions
1. Upload isi folder proyek (atau `ILOK.zip`) ke repository GitHub.
2. Tab **Actions → Build ILOK iOS → Run workflow**.
3. Hasil: artifact **ILOK-iOS-unsigned** berisi `ILOK-unsigned.ipa` (BELUM ditandatangani Apple).

## Memasang di iPhone
IPA harus ditandatangani Apple sebelum bisa dipasang. Pilihan:
| Cara | Syarat | Catatan |
|---|---|---|
| **TestFlight** (terbaik untuk banyak siswa) | Akun Apple Developer (±US$99/tahun) | Buka `ios/` di Xcode pada Mac: `brew install xcodegen && xcodegen generate`, buka `ILOK.xcodeproj`, pilih Team, *Product → Archive → Distribute → TestFlight* |
| Tanda tangan manual | Apple ID gratis + Sideloadly/AltStore | Kedaluwarsa tiap 7 hari, hanya cocok untuk uji coba |
| MDM sekolah | Perangkat terawasi + MDM | Memungkinkan mode kunci satu aplikasi (kiosk) otomatis |

## Fitur anti-curang di iOS
- Keluar dari aplikasi (Home, Control Center, panel notifikasi, app switcher, telepon masuk) → pelanggaran
- **Screenshot terdeteksi** → pelanggaran (iOS tidak mengizinkan memblokir screenshot)
- **Rekam layar / mirroring / AirPlay** → layar ujian ditutup + pelanggaran
- Isi ujian disembunyikan di tampilan app switcher
- Jailbreak ditolak; mirroring/rekam layar aktif ditolak sebelum mulai
- Opsi `requireGuidedAccess`: wajib Akses Terpandu (Guided Access) aktif sebelum ujian
- 3 pelanggaran → terkunci sampai pengawas memasukkan PIN (anti tebak PIN)
- Pelanggaran tersimpan; aplikasi ditutup paksa saat ujian = pelanggaran
- Salin/tempel/seleksi dinonaktifkan, clipboard dibersihkan, domain lain & unduhan diblokir
- Layar tetap menyala; mode layar penuh; iPad: tanpa split view
- Tanda pengenal rahasia ke server — `server/ilok_guard.php` yang sama dipakai untuk Android dan iOS
- Sesi/cookie dihapus saat keluar

## Keluar dari ujian
Ketuk **logo kecil di kiri atas 5 kali** → masukkan PIN pengawas → kembali ke layar awal.

## Batasan iOS
- Tidak ada pemblokiran screenshot; hanya deteksi dan pencatatan.
- Tidak ada "sematkan layar" otomatis. Gunakan Guided Access (diaktifkan siswa) atau MDM.
