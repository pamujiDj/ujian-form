## Fitur
- Blokir screenshot / rekam layar; layar WAJIB disematkan (isi ujian ditutup jika tidak); melepas sematan = ujian langsung terkunci; Back dinonaktifkan; layar penuh & selalu menyala
- Deteksi: keluar aplikasi, panel notifikasi, split screen, layar eksternal/mirroring, aplikasi ditutup paksa
- Cek sebelum mulai: root / emulator, USB debugging, layar eksternal
- 3 pelanggaran → terkunci sampai pengawas memasukkan PIN (anti tebak PIN: jeda 30 detik tiap 5 salah)
- Salin/tempel/seleksi dinonaktifkan, clipboard dibersihkan, domain lain & unduhan diblokir, SSL tidak valid ditolak
- Tanda pengenal rahasia ke server → website hanya bisa dibuka lewat ILOK (lihat `server/PANDUAN_SERVER.md`)
- Kunci perangkat di SERVER + panel guru untuk membuka kunci (lihat server/PANDUAN_SERVER.md)
- Sesi/cookie dihapus saat keluar

## Keluar dari ujian
Ketuk **logo kecil pojok kiri atas 5 kali** → masukkan PIN pengawas.

## Versi iOS
Ada di folder `ios/` — lihat `ios/README_iOS.md`. Workflow: `.github/workflows/ios.yml`.
