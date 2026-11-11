# IKHLAS LOCK (ILOK) v1.1

Aplikasi Android ringan (tanpa library tambahan, Android 5.0+) untuk membuka **https://sas.smpnegeri45sby.sch.id**
(CBT-SPENNEMA) dengan fitur anti-curang.

> Package baru `id.sch.smpn45sby.ilok` → terpasang sebagai aplikasi BARU. Hapus aplikasi lama (eXam Secure) dari HP.

## Membuat APK
**A. GitHub Actions (tanpa install apa pun):** upload isi folder ke repository GitHub → tab *Actions → Build APK → Run workflow*
→ unduh `ILOK-APK` dari *Artifacts* → pasang `app-debug.apk`.
**B. Android Studio:** Open folder ini → *Build → Build APK(s)*.

## WAJIB diganti sebelum dipakai (`Config.java`)
- `PROCTOR_PIN` — PIN pengawas
- `SECRET` — kunci rahasia (samakan dengan `server/ilok_guard.php`)

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
