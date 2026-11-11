<?php
/**
 * ILOK GUARD - hanya mengizinkan akses ujian dari aplikasi IKHLAS LOCK (ILOK),
 * dan MENGUNCI perangkat di server bila pelanggaran mencapai batas.
 *
 * CARA PAKAI (website PHP, mis. CodeIgniter / Laravel / PHP biasa):
 * 1. Upload file ini ke folder web utama (sejajar index.php). Folder harus bisa DITULIS (untuk ilok_devices.json).
 * 2. Pada BARIS PERTAMA index.php (setelah <?php) tambahkan:
 *        require __DIR__ . '/ilok_guard.php';
 * 3. Samakan ILOK_SECRET dengan Config.SECRET di aplikasi, ILOK_WINDOW dengan Config.TOKEN_WINDOW_SEC,
 *    dan ILOK_MAX_VIOLATIONS dengan Config.MAX_VIOLATIONS.
 * 4. GANTI ILOK_ADMIN_KEY (dipakai guru untuk melihat daftar & membuka kunci perangkat).
 * 5. Isi ILOK_ALLOW_PATHS / ILOK_ALLOW_IPS agar halaman admin CBT tetap bisa dibuka dengan browser biasa.
 *
 * ILOK_ENFORCE = false  -> MODE PANTAU: tidak memblokir, hanya mencatat (untuk uji coba).
 *
 * PANEL GURU (buka lewat browser, ganti KUNCI dengan ILOK_ADMIN_KEY):
 *   Daftar perangkat : https://situs-anda/?ilok_admin=list&key=KUNCI
 *   Buka kunci       : https://situs-anda/?ilok_admin=reset&device=ID_PERANGKAT&key=KUNCI
 *   Buka semua kunci : https://situs-anda/?ilok_admin=resetall&key=KUNCI
 */

define('ILOK_SECRET', 'GANTI_DENGAN_KUNCI_RAHASIA_ANDA_123'); // harus sama dengan di aplikasi
define('ILOK_WINDOW', 600);                                    // detik, harus sama dengan di aplikasi
define('ILOK_ENFORCE', true);                                  // true = blokir, false = hanya catat
define('ILOK_SERVER_LOCK', true);                              // kunci perangkat di server bila pelanggaran >= batas
define('ILOK_MAX_VIOLATIONS', 3);                              // samakan dengan Config.MAX_VIOLATIONS
define('ILOK_ADMIN_KEY', 'GANTI_KUNCI_ADMIN_GURU');            // kunci panel guru
define('ILOK_ALLOW_PATHS', array('/admin', '/uploads', '/assets')); // awalan path yang BOLEH tanpa aplikasi
define('ILOK_ALLOW_IPS', array());                             // IP guru/admin, mis. array('192.168.1.10')
define('ILOK_DATA_FILE', __DIR__ . '/ilok_devices.json');

/** Mengembalikan data perangkat bila UA valid, atau null bila tidak valid. */
function ilok_check()
{
    $ua = isset($_SERVER['HTTP_USER_AGENT']) ? $_SERVER['HTTP_USER_AGENT'] : '';
    if (!preg_match('/ILOK\/([\d.]+) t=(\d+) k=([a-f0-9]{16}) d=([a-f0-9]{8}) v=(\d+)/', $ua, $m)) {
        return null;
    }
    $nowWindow = (int) floor(time() / ILOK_WINDOW);
    if (abs($nowWindow - (int) $m[2]) > 1) {
        return null; // token kedaluwarsa / jam HP salah
    }
    $calc = substr(hash_hmac('sha256', $m[2] . '|' . $m[4], ILOK_SECRET), 0, 16);
    if (!hash_equals($calc, $m[3])) {
        return null; // kunci tidak cocok (UA palsu)
    }
    return array('version' => $m[1], 'device' => $m[4], 'violations' => (int) $m[5]);
}

function ilok_log($text)
{
    @file_put_contents(__DIR__ . '/ilok_log.txt', date('Y-m-d H:i:s') . ' ' . $text . "\n", FILE_APPEND | LOCK_EX);
}

function ilok_read_devices()
{
    if (!is_file(ILOK_DATA_FILE)) return array();
    $raw = @file_get_contents(ILOK_DATA_FILE);
    $data = $raw ? json_decode($raw, true) : array();
    return is_array($data) ? $data : array();
}

/** Ubah data perangkat secara aman (terkunci) memakai fungsi $fn($data) -> $data. */
function ilok_modify_devices($fn)
{
    $fh = @fopen(ILOK_DATA_FILE, 'c+');
    if (!$fh) return false;
    flock($fh, LOCK_EX);
    $raw = stream_get_contents($fh);
    $data = $raw ? json_decode($raw, true) : array();
    if (!is_array($data)) $data = array();
    $data = $fn($data);
    ftruncate($fh, 0);
    rewind($fh);
    fwrite($fh, json_encode($data));
    fflush($fh);
    flock($fh, LOCK_UN);
    fclose($fh);
    return true;
}

/** Catat pelanggaran per perangkat; kembalikan true bila perangkat terkunci di server. */
function ilok_track($device, $v, $ip)
{
    $data = ilok_read_devices();
    $rec = isset($data[$device]) ? $data[$device] : null;
    $needWrite = ($rec === null) || ($v > $rec['v']) || (time() - $rec['last'] > 60);
    if ($needWrite) {
        ilok_modify_devices(function ($d) use ($device, $v, $ip) {
            $r = isset($d[$device]) ? $d[$device] : array('v' => 0, 'locked' => false, 'first' => time());
            if ($v > $r['v']) $r['v'] = $v;
            if ($r['v'] >= ILOK_MAX_VIOLATIONS) $r['locked'] = true;
            $r['last'] = time();
            $r['ip'] = $ip;
            $d[$device] = $r;
            return $d;
        });
        $data = ilok_read_devices();
        $rec = isset($data[$device]) ? $data[$device] : null;
    }
    return ($rec !== null && !empty($rec['locked']));
}

function ilok_page($status, $title, $message)
{
    http_response_code($status);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><html lang="id"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width,initial-scale=1"><title>' . htmlspecialchars($title) . '</title>'
        . '<style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;'
        . 'background:linear-gradient(#0A0F2C,#2A1B5E);font-family:sans-serif;color:#fff;text-align:center;padding:24px}'
        . '.c{max-width:420px}h1{font-size:22px}p{color:#B8C6FF;line-height:1.6}</style></head><body><div class="c">'
        . '<div style="font-size:56px">&#128274;</div><h1>' . htmlspecialchars($title) . '</h1>'
        . '<p>' . $message . '</p></div></body></html>';
    exit;
}

/** Panel guru. */
function ilok_admin()
{
    $key = isset($_GET['key']) ? (string) $_GET['key'] : '';
    if (!hash_equals(ILOK_ADMIN_KEY, $key)) {
        ilok_page(403, 'Akses ditolak', 'Kunci admin salah.');
    }
    $act = (string) $_GET['ilok_admin'];
    $keyQ = urlencode($key);
    if ($act === 'reset' && isset($_GET['device'])) {
        $dev = preg_replace('/[^a-f0-9]/', '', (string) $_GET['device']);
        ilok_modify_devices(function ($d) use ($dev) { unset($d[$dev]); return $d; });
        ilok_log("ADMIN buka kunci device=$dev");
        ilok_page(200, 'Kunci dibuka', 'Perangkat <b>' . htmlspecialchars($dev) . '</b> dapat melanjutkan ujian.<br><br>'
            . '<a style="color:#9DB4FF" href="?ilok_admin=list&key=' . $keyQ . '">Kembali ke daftar</a>');
    }
    if ($act === 'resetall') {
        ilok_modify_devices(function ($d) { return array(); });
        ilok_log('ADMIN buka semua kunci');
        ilok_page(200, 'Semua kunci dibuka', '<a style="color:#9DB4FF" href="?ilok_admin=list&key=' . $keyQ . '">Kembali ke daftar</a>');
    }
    $data = ilok_read_devices();
    uasort($data, function ($a, $b) { return $b['last'] - $a['last']; });
    http_response_code(200);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        . '<title>ILOK - Daftar Perangkat</title><style>body{font-family:sans-serif;padding:16px}table{border-collapse:collapse;width:100%}'
        . 'td,th{border:1px solid #ccc;padding:6px 8px;font-size:14px;text-align:left}th{background:#eef}.k{color:#c00;font-weight:bold}</style></head><body>'
        . '<h2>ILOK - Daftar Perangkat (' . count($data) . ')</h2>'
        . '<p><a href="?ilok_admin=resetall&key=' . $keyQ . '" onclick="return confirm(\'Buka SEMUA kunci?\')">Buka semua kunci</a></p>'
        . '<table><tr><th>ID Perangkat</th><th>Pelanggaran</th><th>Status</th><th>Terakhir</th><th>IP</th><th>Aksi</th></tr>';
    foreach ($data as $id => $r) {
        $locked = !empty($r['locked']);
        echo '<tr><td>' . htmlspecialchars($id) . '</td><td>' . (int) $r['v'] . '</td><td'
            . ($locked ? ' class="k">TERKUNCI' : '>Aktif') . '</td><td>' . date('d/m H:i:s', $r['last']) . '</td><td>'
            . htmlspecialchars($r['ip']) . '</td><td>' . ($locked || $r['v'] > 0
                ? '<a href="?ilok_admin=reset&device=' . htmlspecialchars($id) . '&key=' . $keyQ . '">Buka kunci</a>' : '') . '</td></tr>';
    }
    echo '</table></body></html>';
    exit;
}

(function () {
    if (isset($_GET['ilok_admin'])) {
        ilok_admin(); // selalu diproses lebih dulu, sebelum pemeriksaan lain
    }

    $path = parse_url(isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : '/', PHP_URL_PATH);
    $ip = isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : '';

    foreach (ILOK_ALLOW_PATHS as $p) {
        if (strpos($path, $p) === 0) return;
    }
    if (in_array($ip, ILOK_ALLOW_IPS, true)) return;

    $info = ilok_check();
    if ($info !== null) {
        $GLOBALS['ILOK_INFO'] = $info; // tersedia untuk kode lain: device id & jumlah pelanggaran
        $locked = ILOK_SERVER_LOCK ? ilok_track($info['device'], $info['violations'], $ip) : false;
        if ($info['violations'] > 0) {
            ilok_log("PELANGGARAN ip=$ip device={$info['device']} v={$info['violations']} path=$path");
        }
        if ($locked && ILOK_ENFORCE) {
            ilok_page(403, 'Ujian dikunci',
                'Perangkat ini dikunci karena pelanggaran.<br>Hubungi pengawas.<br><small>ID: ' . htmlspecialchars($info['device']) . '</small>');
        }
        return;
    }

    $ua = isset($_SERVER['HTTP_USER_AGENT']) ? $_SERVER['HTTP_USER_AGENT'] : '-';
    ilok_log("TANPA-APLIKASI ip=$ip path=$path ua=" . substr($ua, 0, 120));
    if (!ILOK_ENFORCE) return;

    ilok_page(403, 'Ujian hanya dapat dibuka lewat aplikasi IKHLAS LOCK (ILOK)',
        'Buka aplikasi ILOK di HP Anda. Pastikan tanggal &amp; jam HP diatur otomatis.');
})();
