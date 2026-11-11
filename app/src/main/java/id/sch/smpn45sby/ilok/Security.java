package id.sch.smpn45sby.ilok;

import android.content.Context;
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.provider.Settings;
import android.view.Display;

import java.io.File;
import java.security.MessageDigest;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** Fungsi bantu keamanan: tanda pengenal ke server, deteksi root/emulator/ADB/layar eksternal. */
final class Security {
    private Security() {}

    private static String cachedDeviceId;

    /** ID perangkat singkat (8 hex) dari ANDROID_ID yang di-hash. */
    static String deviceId(Context c) {
        if (cachedDeviceId == null) {
            String id = Settings.Secure.getString(c.getContentResolver(), Settings.Secure.ANDROID_ID);
            if (id == null) id = "unknown";
            cachedDeviceId = hex(sha256(id)).substring(0, 8);
        }
        return cachedDeviceId;
    }

    /**
     * User-Agent = UA asli + " ILOK/1.1 t=<jendela waktu> k=<HMAC> d=<id perangkat> v=<pelanggaran>".
     * Server memverifikasi k = HMAC-SHA256(SECRET, t + "|" + d)[0..16]. Token berganti tiap jendela waktu,
     * jadi UA yang disalin dari perangkat lain tidak dapat dipakai ulang.
     */
    static String buildUserAgent(Context c, String base, int violations) {
        long t = System.currentTimeMillis() / 1000L / Config.TOKEN_WINDOW_SEC;
        String d = deviceId(c);
        String k = hmacHex(Config.SECRET, t + "|" + d).substring(0, 16);
        return base + " ILOK/" + Config.APP_VERSION + " t=" + t + " k=" + k + " d=" + d + " v=" + violations;
    }

    static boolean isRootedOrEmulator() {
        String[] paths = {"/system/bin/su", "/system/xbin/su", "/sbin/su", "/system/su", "/su/bin/su",
                "/data/local/xbin/su", "/data/local/bin/su", "/system/app/Superuser.apk",
                "/system/xbin/daemonsu"};
        for (String p : paths) {
            if (new File(p).exists()) return true;
        }
        String tags = Build.TAGS;
        if (tags != null && tags.contains("test-keys")) return true;
        String fp = String.valueOf(Build.FINGERPRINT);
        String hw = String.valueOf(Build.HARDWARE);
        String model = String.valueOf(Build.MODEL);
        String prod = String.valueOf(Build.PRODUCT);
        return fp.startsWith("generic") || fp.contains("vbox") || fp.contains("emulator")
                || hw.contains("goldfish") || hw.contains("ranchu") || hw.contains("vbox")
                || model.contains("Emulator") || model.contains("Android SDK built for")
                || String.valueOf(Build.MANUFACTURER).contains("Genymotion")
                || prod.contains("sdk") || prod.contains("emulator");
    }

    static boolean isUsbDebugging(Context c) {
        try {
            return Settings.Global.getInt(c.getContentResolver(), Settings.Global.ADB_ENABLED, 0) == 1;
        } catch (Exception e) {
            return false;
        }
    }

    /** Ada layar tambahan (Cast / Miracast / HDMI)? */
    static boolean hasExternalDisplay(Context c) {
        try {
            DisplayManager dm = (DisplayManager) c.getSystemService(Context.DISPLAY_SERVICE);
            if (dm == null) return false;
            for (Display d : dm.getDisplays()) {
                if (d.getDisplayId() != Display.DEFAULT_DISPLAY
                        && (d.getFlags() & Display.FLAG_PRIVATE) == 0) {
                    return true;
                }
            }
        } catch (Exception ignored) {
        }
        return false;
    }

    // ------------------------------------------------------------ util

    private static byte[] sha256(String s) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(s.getBytes("UTF-8"));
        } catch (Exception e) {
            return new byte[32];
        }
    }

    private static String hmacHex(String key, String msg) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key.getBytes("UTF-8"), "HmacSHA256"));
            return hex(mac.doFinal(msg.getBytes("UTF-8")));
        } catch (Exception e) {
            return "0000000000000000000000000000000000000000000000000000000000000000";
        }
    }

    private static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x));
        return sb.toString();
    }
}
