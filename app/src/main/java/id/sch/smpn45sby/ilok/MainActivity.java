package id.sch.smpn45sby.ilok;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.hardware.display.DisplayManager;
import android.graphics.Color;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.View;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.webkit.CookieManager;
import android.webkit.JsPromptResult;
import android.webkit.JsResult;
import android.webkit.SslErrorHandler;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebStorage;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

/**
 * IKHLAS LOCK (ILOK) - penampil web ujian dengan fitur anti-curang.
 * Tanpa library tambahan agar ringan dan kompatibel Android 5.0+.
 */
public class MainActivity extends Activity {

    private static final int MODE_UNLOCK = 1;
    private static final int MODE_EXIT = 2;
    private static final int MODE_NEEDPIN = 3;

    /** Mematikan seleksi/salin/tempel/klik-kanan di dalam halaman web. */
    private static final String JS_LOCKDOWN =
            "(function(){try{"
            + "if(window.__examLocked)return;window.__examLocked=true;"
            + "var st=document.createElement('style');"
            + "st.textContent='*{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}"
            + "input,textarea,[contenteditable=true]{-webkit-user-select:text;user-select:text}';"
            + "(document.head||document.documentElement).appendChild(st);"
            + "['copy','cut','paste','contextmenu','dragstart'].forEach(function(e){"
            + "document.addEventListener(e,function(ev){ev.preventDefault();return false;},true);});"
            + "}catch(e){}})();";

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable uaRefresher = new Runnable() {
        @Override public void run() {
            refreshUa();
            handler.postDelayed(this, 60000);
        }
    };
    private final Runnable pinWatcher = new Runnable() {
        @Override public void run() {
            checkPin();
            handler.postDelayed(this, 1000);
        }
    };
    private final Runnable hideBanner = new Runnable() {
        @Override public void run() { tvBanner.setVisibility(View.GONE); }
    };

    private View startScreen, examScreen, errorView, lockView;
    private WebView webView;
    private ProgressBar progress;
    private TextView tvViolation, tvBanner, tvErrorMsg, tvLockTitle, tvLockMsg, tvPinError, tvStartInfo;
    private EditText etPin;
    private Button btnLockCancel, btnUnlock;
    private SharedPreferences prefs;
    private String baseUa;
    private DisplayManager.DisplayListener displayListener;

    private boolean examActive = false;
    private boolean awayCounted = false;
    private boolean dialogOpen = false;
    private boolean hasError = false;
    private long graceUntil = 0;
    private String pendingMsg = null;
    private int overlayMode = MODE_UNLOCK;
    private boolean wasPinned = false;
    private long pinGraceUntil = 0;
    private String lockReason = null;
    private int tapCount = 0;
    private long lastTap = 0;
    private int pinFails = 0;
    private long pinBlockedUntil = 0;

    // ------------------------------------------------------------------ lifecycle

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Blokir screenshot, rekam layar, dan thumbnail di daftar aplikasi terbaru.
        // Layar tetap menyala selama ujian.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE
                | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        setContentView(R.layout.activity_main);
        prefs = getSharedPreferences("exam", MODE_PRIVATE);

        startScreen = findViewById(R.id.startScreen);
        examScreen = findViewById(R.id.examScreen);
        errorView = findViewById(R.id.errorView);
        lockView = findViewById(R.id.lockView);
        webView = (WebView) findViewById(R.id.webView);
        progress = (ProgressBar) findViewById(R.id.progress);
        tvViolation = (TextView) findViewById(R.id.tvViolation);
        tvBanner = (TextView) findViewById(R.id.tvBanner);
        tvErrorMsg = (TextView) findViewById(R.id.tvErrorMsg);
        tvLockTitle = (TextView) findViewById(R.id.tvLockTitle);
        tvLockMsg = (TextView) findViewById(R.id.tvLockMsg);
        tvPinError = (TextView) findViewById(R.id.tvPinError);
        tvStartInfo = (TextView) findViewById(R.id.tvStartInfo);
        etPin = (EditText) findViewById(R.id.etPin);
        btnLockCancel = (Button) findViewById(R.id.btnLockCancel);
        btnUnlock = (Button) findViewById(R.id.btnUnlock);

        setupWebView();
        ((TextView) findViewById(R.id.tvDeviceId)).setText(
                "ID Perangkat: " + Security.deviceId(this) + " • ILOK v" + Config.APP_VERSION);
        registerDisplayWatcher();

        findViewById(R.id.btnStart).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { onStartClicked(); }
        });
        findViewById(R.id.btnRetry).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { retryLoad(); }
        });
        // Tombol "Muat ulang" di bilah atas: memuat ulang halaman ujian (sesi tetap, tidak keluar dari ujian).
        findViewById(R.id.btnRefresh).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                refreshUa();
                retryLoad();
            }
        });
        btnUnlock.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { submitPin(); }
        });
        btnLockCancel.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { hideOverlay(); }
        });
        etPin.setOnEditorActionListener(new TextView.OnEditorActionListener() {
            @Override public boolean onEditorAction(TextView v, int actionId, android.view.KeyEvent e) {
                submitPin();
                return true;
            }
        });
        // Ketuk logo 5x berturut-turut = menu keluar khusus pengawas.
        findViewById(R.id.imgHeaderLogo).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                long now = SystemClock.elapsedRealtime();
                tapCount = (now - lastTap < 1500) ? tapCount + 1 : 1;
                lastTap = now;
                if (tapCount >= 5) {
                    tapCount = 0;
                    showOverlay(MODE_EXIT, true);
                }
            }
        });

        // Aplikasi ditutup paksa saat ujian berlangsung => dicatat sebagai pelanggaran.
        if (savedInstanceState == null && prefs.getBoolean("inExam", false)) {
            prefs.edit().putBoolean("inExam", false).commit();
            addViolation();
            tvStartInfo.setText("⚠ Aplikasi ditutup saat ujian berlangsung. Pelanggaran dicatat ("
                    + violations() + "/" + Config.MAX_VIOLATIONS + ").");
            tvStartInfo.setVisibility(View.VISIBLE);
        }
        if (violations() >= Config.MAX_VIOLATIONS) {
            tvStartInfo.setText("🔒 Ujian terkunci. Hubungi pengawas untuk membukanya.");
            tvStartInfo.setVisibility(View.VISIBLE);
        }
        updateViolationUi();
        playIntroAnimation();
    }

    @Override
    protected void onResume() {
        super.onResume();
        hideSystemUi();
        if (examActive) {
            clearClipboard();
            ensurePinned();
        }
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        try {
            DisplayManager dm = (DisplayManager) getSystemService(DISPLAY_SERVICE);
            if (dm != null && displayListener != null) dm.unregisterDisplayListener(displayListener);
        } catch (Exception ignored) {
        }
        if (webView != null) {
            webView.stopLoading();
            webView.destroy();
        }
        super.onDestroy();
    }

    // ------------------------------------------------------------------ anti-curang

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemUi();
        if (!examActive) return;

        if (hasFocus) {
            clearClipboard();
            if (awayCounted) {
                awayCounted = false;
                afterViolation();
            }
        } else {
            // Fokus hilang: panel notifikasi, aplikasi lain, tombol home/recent, dsb.
            if (dialogOpen || SystemClock.elapsedRealtime() < graceUntil) return;
            if (!awayCounted) {
                awayCounted = true;
                flagViolation("Anda meninggalkan layar ujian.");
            }
        }
    }

    /** Mode layar terbagi (split screen) / jendela mengambang. */
    @Override
    public void onMultiWindowModeChanged(boolean isInMultiWindowMode) {
        super.onMultiWindowModeChanged(isInMultiWindowMode);
        if (examActive && isInMultiWindowMode) {
            flagViolation("Mode layar terbagi terdeteksi.");
            afterViolation();
        }
    }

    @Override
    public void onBackPressed() {
        if (lockView.getVisibility() == View.VISIBLE) {
            if (btnLockCancel.getVisibility() == View.VISIBLE) hideOverlay();
            return;
        }
        if (!examActive) {
            super.onBackPressed();
            return;
        }
        if (Config.ALLOW_BACK && webView.canGoBack()) webView.goBack();
        // selain itu: tombol Back dinonaktifkan selama ujian
    }

    private void flagViolation(String msg) {
        addViolation();
        pendingMsg = "⚠ Pelanggaran " + violations() + "/" + Config.MAX_VIOLATIONS + ": " + msg;
    }

    private void afterViolation() {
        if (pendingMsg == null) return;
        if (violations() >= Config.MAX_VIOLATIONS) {
            showOverlay(MODE_UNLOCK, false);
        } else {
            showBanner(pendingMsg);
        }
        pendingMsg = null;
    }

    private int violations() { return prefs.getInt("violations", 0); }

    private void addViolation() {
        prefs.edit().putInt("violations", violations() + 1).commit();
        updateViolationUi();
        refreshUa();
    }

    private void updateViolationUi() {
        int v = violations();
        tvViolation.setText("Pelanggaran " + v + "/" + Config.MAX_VIOLATIONS);
        tvViolation.setBackgroundResource(v > 0 ? R.drawable.bg_banner : R.drawable.bg_pill);
    }

    @SuppressWarnings("deprecation")
    private boolean isPinned() {
        ActivityManager am = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
        if (am == null) return false;
        if (Build.VERSION.SDK_INT >= 23) {
            return am.getLockTaskModeState() != ActivityManager.LOCK_TASK_MODE_NONE;
        }
        return am.isInLockTaskMode();
    }

    /** Menyematkan layar (screen pinning) agar tombol Home / Recent tidak berfungsi. */
    private void ensurePinned() {
        if (!examActive || isPinned()) return;
        try {
            graceUntil = SystemClock.elapsedRealtime() + 3000;
            startLockTask();
        } catch (Exception ignored) {
        }
    }

    /**
     * Dipanggil tiap detik. Jika layar tidak tersemat, isi ujian ditutup. Jika layar yang tadinya
     * tersemat dilepas siswa, ujian langsung terkunci sampai pengawas memasukkan PIN.
     */
    private void checkPin() {
        if (!examActive || !Config.REQUIRE_PINNING) return;
        if (isPinned()) {
            wasPinned = true;
            if (lockView.getVisibility() == View.VISIBLE && overlayMode == MODE_NEEDPIN) hideOverlay();
            return;
        }
        if (SystemClock.elapsedRealtime() < pinGraceUntil) return;
        if (wasPinned) {
            wasPinned = false;
            if (Config.UNPIN_LOCKS_EXAM) {
                lockReason = "Sematkan layar dilepas saat ujian.";
                prefs.edit().putInt("violations", Config.MAX_VIOLATIONS).commit();
                updateViolationUi();
                refreshUa();
                showOverlay(MODE_UNLOCK, false);
            } else {
                flagViolation("Sematkan layar dilepas.");
                afterViolation();
            }
            return;
        }
        if (lockView.getVisibility() != View.VISIBLE) showOverlay(MODE_NEEDPIN, false);
    }

    private void clearClipboard() {
        try {
            ClipboardManager cm = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (cm != null) cm.setPrimaryClip(ClipData.newPlainText("", ""));
        } catch (Exception ignored) {
        }
    }

    // ------------------------------------------------------------------ alur ujian

    private void onStartClicked() {
        if (violations() >= Config.MAX_VIOLATIONS) {
            showOverlay(MODE_UNLOCK, true);
            return;
        }
        String problem = preflight();
        if (problem != null) {
            tvStartInfo.setText("⛔ " + problem);
            tvStartInfo.setVisibility(View.VISIBLE);
            return;
        }
        startExam();
    }

    /** Pemeriksaan keamanan perangkat sebelum ujian dimulai. */
    private String preflight() {
        if (Config.BLOCK_ROOT_EMULATOR && Security.isRootedOrEmulator()) {
            return "Perangkat root / emulator tidak diizinkan untuk ujian.";
        }
        if (Config.BLOCK_USB_DEBUGGING && Security.isUsbDebugging(this)) {
            return "Matikan \"Debugging USB\" di Opsi Pengembang, lalu coba lagi.";
        }
        if (Security.hasExternalDisplay(this)) {
            return "Layar eksternal / mirroring terdeteksi. Putuskan dulu, lalu coba lagi.";
        }
        return null;
    }

    private void registerDisplayWatcher() {
        try {
            DisplayManager dm = (DisplayManager) getSystemService(DISPLAY_SERVICE);
            if (dm == null) return;
            displayListener = new DisplayManager.DisplayListener() {
                @Override public void onDisplayAdded(int displayId) {
                    if (examActive && Security.hasExternalDisplay(MainActivity.this)) {
                        flagViolation("Layar eksternal / mirroring terdeteksi.");
                        afterViolation();
                    }
                }
                @Override public void onDisplayRemoved(int displayId) { }
                @Override public void onDisplayChanged(int displayId) { }
            };
            dm.registerDisplayListener(displayListener, handler);
        } catch (Exception ignored) {
        }
    }

    private void refreshUa() {
        if (baseUa == null || webView == null) return;
        webView.getSettings().setUserAgentString(Security.buildUserAgent(this, baseUa, violations()));
    }

    private void startExam() {
        examActive = true;
        awayCounted = false;
        prefs.edit().putBoolean("inExam", true).commit();
        startScreen.setVisibility(View.GONE);
        examScreen.setVisibility(View.VISIBLE);
        tvStartInfo.setVisibility(View.GONE);
        clearClipboard();
        refreshUa();
        handler.removeCallbacks(uaRefresher);
        handler.postDelayed(uaRefresher, 60000);
        ensurePinned();
        // Beri waktu menekan "Mulai" pada dialog sematkan layar, lalu pantau tiap detik.
        wasPinned = false;
        pinGraceUntil = SystemClock.elapsedRealtime() + 8000;
        handler.removeCallbacks(pinWatcher);
        if (Config.REQUIRE_PINNING) handler.postDelayed(pinWatcher, 1000);
        hideSystemUi();
        if (webView.getUrl() == null) webView.loadUrl(Config.EXAM_URL);
    }

    private void exitExam() {
        examActive = false;
        handler.removeCallbacks(pinWatcher);
        prefs.edit().putBoolean("inExam", false).putInt("violations", 0).commit();
        try { stopLockTask(); } catch (Exception ignored) { }
        clearWebData();
        finishAndRemoveTask();
    }

    private void clearWebData() {
        try {
            CookieManager.getInstance().removeAllCookies(null);
            CookieManager.getInstance().flush();
            webView.clearCache(true);
            webView.clearHistory();
            WebStorage.getInstance().deleteAllData();
        } catch (Exception ignored) {
        }
    }

    private void retryLoad() {
        hasError = false;
        errorView.setVisibility(View.GONE);
        String u = webView.getUrl();
        if (u == null || u.startsWith("about:") || u.startsWith("data:")) {
            webView.loadUrl(Config.EXAM_URL);
        } else {
            webView.reload();
        }
    }

    // ------------------------------------------------------------------ overlay PIN

    private void showOverlay(int mode, boolean cancelable) {
        overlayMode = mode;
        boolean needPin = (mode == MODE_NEEDPIN);
        if (mode == MODE_UNLOCK) {
            tvLockTitle.setText("Ujian Terkunci");
            String why = (lockReason != null) ? lockReason
                    : "Pelanggaran sudah mencapai batas (" + Config.MAX_VIOLATIONS + ").";
            tvLockMsg.setText(why + "\nMinta pengawas memasukkan PIN untuk melanjutkan.");
            btnUnlock.setText("BUKA KUNCI");
        } else if (needPin) {
            tvLockTitle.setText("Layar Harus Disematkan");
            tvLockMsg.setText("Ujian hanya bisa dikerjakan saat layar disematkan.\n"
                    + "Ketuk tombol di bawah, lalu pilih \"Mulai\" atau \"Got it\".");
            btnUnlock.setText("SEMATKAN LAYAR");
        } else {
            tvLockTitle.setText("Keluar dari Ujian");
            tvLockMsg.setText("Khusus pengawas.\nMasukkan PIN untuk keluar dari mode ujian.");
            btnUnlock.setText("KELUAR");
        }
        btnLockCancel.setVisibility(cancelable ? View.VISIBLE : View.GONE);
        etPin.setVisibility(needPin ? View.GONE : View.VISIBLE);
        tvPinError.setVisibility(needPin ? View.GONE : View.INVISIBLE);
        etPin.setText("");
        lockView.setVisibility(View.VISIBLE);
        if (!needPin) {
            etPin.requestFocus();
            etPin.postDelayed(new Runnable() {
                @Override public void run() {
                    InputMethodManager imm = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
                    if (imm != null) imm.showSoftInput(etPin, InputMethodManager.SHOW_IMPLICIT);
                }
            }, 250);
        }
    }

    private void hideOverlay() {
        InputMethodManager imm = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
        if (imm != null) imm.hideSoftInputFromWindow(etPin.getWindowToken(), 0);
        lockView.setVisibility(View.GONE);
        hideSystemUi();
    }

    private void submitPin() {
        if (overlayMode == MODE_NEEDPIN) {
            ensurePinned();
            pinGraceUntil = SystemClock.elapsedRealtime() + 8000;
            return;
        }
        long now = SystemClock.elapsedRealtime();
        if (now < pinBlockedUntil) {
            long sec = (pinBlockedUntil - now) / 1000 + 1;
            tvPinError.setText("Terlalu banyak percobaan. Coba lagi dalam " + sec + " detik.");
            tvPinError.setVisibility(View.VISIBLE);
            return;
        }
        String pin = etPin.getText().toString();
        if (Config.PROCTOR_PIN.equals(pin)) {
            pinFails = 0;
            hideOverlay();
            if (overlayMode == MODE_UNLOCK) {
                prefs.edit().putInt("violations", 0).commit();
                updateViolationUi();
                lockReason = null;
                refreshUa();
                tvStartInfo.setVisibility(View.GONE);
                if (!examActive) {
                    startExam();
                } else {
                    wasPinned = false;
                    ensurePinned(); // sematkan ulang setelah pengawas membuka kunci
                    pinGraceUntil = SystemClock.elapsedRealtime() + 8000;
                }
            } else {
                exitExam();
            }
        } else {
            pinFails++;
            if (pinFails % 5 == 0) pinBlockedUntil = now + 30000;
            tvPinError.setText("PIN salah");
            tvPinError.setVisibility(View.VISIBLE);
            etPin.setText("");
        }
    }

    // ------------------------------------------------------------------ WebView

    @SuppressLint("SetJavaScriptEnabled")
    @SuppressWarnings("deprecation")
    private void setupWebView() {
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setSupportMultipleWindows(false);
        s.setJavaScriptCanOpenWindowsAutomatically(false);
        s.setGeolocationEnabled(false);
        s.setSaveFormData(false);
        s.setTextZoom(100);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        baseUa = s.getUserAgentString();
        refreshUa();

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(webView, true); // dibutuhkan agar Google Form / Microsoft Forms tampil di dalam halaman

        webView.setBackgroundColor(Color.WHITE);
        webView.setOverScrollMode(View.OVER_SCROLL_NEVER);
        webView.setLongClickable(false);
        webView.setHapticFeedbackEnabled(false);
        webView.setOnLongClickListener(new View.OnLongClickListener() {
            @Override public boolean onLongClick(View v) { return true; }
        });
        webView.setDownloadListener(new android.webkit.DownloadListener() {
            @Override
            public void onDownloadStart(String url, String ua, String cd, String mime, long len) {
                toast("Unduhan diblokir selama ujian.");
            }
        });

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return !allow(Uri.parse(url));
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                // Isi iframe (Google Form, Drive, Microsoft Forms) dibiarkan; domain yang boleh
                // ditampilkan sudah dibatasi oleh website. Pembatasan domain hanya untuk halaman utama.
                if (!request.isForMainFrame()) return false;
                return !allow(request.getUrl());
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                hasError = false;
                progress.setProgress(0);
                progress.setVisibility(View.VISIBLE);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                progress.setVisibility(View.GONE);
                if (!hasError) errorView.setVisibility(View.GONE);
                view.evaluateJavascript(JS_LOCKDOWN, null);
            }

            @Override
            public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
                if (Build.VERSION.SDK_INT < 23) {
                    showError("Periksa koneksi internet Anda lalu coba lagi.");
                }
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    showError("Periksa koneksi internet Anda lalu coba lagi.");
                }
            }

            @Override
            public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
                handler.cancel(); // jangan pernah lanjut jika sertifikat tidak valid
                showError("Sertifikat keamanan tidak valid.\nPastikan tanggal & jam perangkat benar "
                        + "dan perbarui \"Android System WebView\" di Play Store.");
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                progress.setProgress(newProgress);
                progress.setVisibility(newProgress < 100 ? View.VISIBLE : View.GONE);
            }

            @Override
            public boolean onJsAlert(WebView view, String url, String message, JsResult result) {
                showJsDialog(message, result, false);
                return true;
            }

            @Override
            public boolean onJsConfirm(WebView view, String url, String message, JsResult result) {
                showJsDialog(message, result, true);
                return true;
            }

            @Override
            public boolean onJsPrompt(WebView view, String url, String message, String def, JsPromptResult result) {
                result.cancel();
                return true;
            }

            @Override
            public boolean onJsBeforeUnload(WebView view, String url, String message, JsResult result) {
                result.confirm();
                return true;
            }
        });
    }

    private boolean allow(Uri uri) {
        String scheme = uri.getScheme();
        String host = uri.getHost();
        boolean ok = false;
        if (host != null && ("https".equals(scheme) || "http".equals(scheme))) {
            for (String h : Config.ALLOWED_HOSTS) {
                if (host.equals(h) || host.endsWith("." + h)) { ok = true; break; }
            }
        }
        if (!ok) toast("Halaman ini tidak diizinkan selama ujian.");
        return ok;
    }

    private void showError(String msg) {
        hasError = true;
        tvErrorMsg.setText(msg);
        progress.setVisibility(View.GONE);
        errorView.setVisibility(View.VISIBLE);
    }

    private void showJsDialog(String msg, final JsResult r, boolean withCancel) {
        dialogOpen = true; // dialog bawaan web tidak dihitung sebagai pelanggaran
        AlertDialog.Builder b = new AlertDialog.Builder(this)
                .setMessage(msg)
                .setCancelable(false)
                .setPositiveButton("OK", new android.content.DialogInterface.OnClickListener() {
                    @Override public void onClick(android.content.DialogInterface d, int w) { r.confirm(); }
                });
        if (withCancel) {
            b.setNegativeButton("Batal", new android.content.DialogInterface.OnClickListener() {
                @Override public void onClick(android.content.DialogInterface d, int w) { r.cancel(); }
            });
        }
        AlertDialog dlg = b.create();
        dlg.setOnDismissListener(new android.content.DialogInterface.OnDismissListener() {
            @Override public void onDismiss(android.content.DialogInterface d) { dialogOpen = false; }
        });
        dlg.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        dlg.show();
    }

    // ------------------------------------------------------------------ UI helper

    @SuppressWarnings("deprecation")
    private void hideSystemUi() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    }

    private void showBanner(String msg) {
        tvBanner.setText(msg);
        tvBanner.setVisibility(View.VISIBLE);
        handler.removeCallbacks(hideBanner);
        handler.postDelayed(hideBanner, 6000);
    }

    private void toast(String msg) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show();
    }

    private void playIntroAnimation() {
        View logo = findViewById(R.id.imgLogo);
        View card = findViewById(R.id.cardRules);
        View btn = findViewById(R.id.btnStart);
        logo.setAlpha(0f);
        logo.setTranslationY(-30f);
        logo.animate().alpha(1f).translationY(0f).setDuration(700).start();
        card.setAlpha(0f);
        card.setTranslationY(40f);
        card.animate().alpha(1f).translationY(0f).setStartDelay(250).setDuration(600).start();
        btn.setAlpha(0f);
        btn.animate().alpha(1f).setStartDelay(550).setDuration(500).start();
    }
}
