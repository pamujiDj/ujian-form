import UIKit
import WebKit

/// IKHLAS LOCK (ILOK) - penampil web ujian dengan fitur anti-curang untuk iOS.
final class MainViewController: UIViewController {

    /// Mematikan seleksi / salin / tempel / klik lama di dalam halaman web.
    private static let jsLockdown = """
    (function(){try{
    if(window.__ilokLocked)return;window.__ilokLocked=true;
    var st=document.createElement('style');
    st.textContent='*{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}input,textarea,[contenteditable=true]{-webkit-user-select:text;user-select:text}';
    (document.head||document.documentElement).appendChild(st);
    ['copy','cut','paste','contextmenu','dragstart'].forEach(function(e){document.addEventListener(e,function(ev){ev.preventDefault();return false;},true);});
    }catch(e){}})();
    """

    private enum OverlayMode { case unlock, exit }

    // MARK: - State

    private let defaults = UserDefaults.standard
    private var examActive = false
    private var awayCounted = false
    private var captureFlagged = false
    private var hasError = false
    private var graceUntil = Date.distantPast
    private var pendingMsg: String?
    private var baseUA: String?
    private var uaTimer: Timer?
    private var bannerWork: DispatchWorkItem?
    private var tapCount = 0
    private var lastTap = Date.distantPast
    private var pinFails = 0
    private var pinBlockedUntil = Date.distantPast
    private var overlayMode: OverlayMode = .unlock
    private var progressObs: NSKeyValueObservation?

    private var violations: Int {
        get { return defaults.integer(forKey: "violations") }
        set { defaults.set(newValue, forKey: "violations") }
    }

    // MARK: - Views

    private let bgView = GradientView(colors: [0x0A0F2C, 0x141B4D, 0x2A1B5E], vertical: true)
    private let startScroll = UIScrollView()
    private let logoView = UIImageView(image: UIImage(named: "logo"))
    private let cardView = UIView()
    private let lblStartInfo = UILabel()
    private let lblDevice = UILabel()
    private let btnStart = GradientButton()

    private let examContainer = UIView()
    private let header = GradientView(colors: [0x0A0F2C, 0x2A1B5E], vertical: false)
    private let btnHeaderLogo = UIButton(type: .custom)
    private let lblViolation = PaddedLabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let banner = PaddedLabel()
    private let errorView = UIView()
    private let lblError = UILabel()
    private let btnRetry = GradientButton()

    private let lockView = GradientView(colors: [0x0A0F2C, 0x141B4D, 0x2A1B5E], vertical: true)
    private let lblLockTitle = UILabel()
    private let lblLockMsg = UILabel()
    private let pinField = UITextField()
    private let lblPinError = UILabel()
    private let btnUnlock = GradientButton()
    private let btnCancel = UIButton(type: .system)

    private let privacyCover = UIView()
    private let lblCover = UILabel()

    private let webView: WKWebView = {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        cfg.dataDetectorTypes = []
        let script = WKUserScript(source: MainViewController.jsLockdown,
                                  injectionTime: .atDocumentEnd,
                                  forMainFrameOnly: false)
        cfg.userContentController.addUserScript(script)
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsLinkPreview = false
        wv.allowsBackForwardNavigationGestures = false
        wv.scrollView.pinchGestureRecognizer?.isEnabled = false
        wv.isOpaque = true
        wv.backgroundColor = .white
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(hex: 0x0A0F2C)

        buildStart()
        buildExam()
        buildLock()
        buildPrivacyCover()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            self?.progressView.progress = Float(wv.estimatedProgress)
            self?.progressView.isHidden = wv.estimatedProgress >= 1
        }

        registerObservers()
        lblDevice.text = "ID Perangkat: \(Security.deviceId) • ILOK v\(Config.appVersion)"

        // Aplikasi ditutup saat ujian berlangsung => dicatat sebagai pelanggaran.
        if defaults.bool(forKey: "inExam") {
            defaults.set(false, forKey: "inExam")
            violations += 1
            showStartInfo("⚠ Aplikasi ditutup saat ujian berlangsung. Pelanggaran dicatat (\(violations)/\(Config.maxViolations)).")
        }
        if violations >= Config.maxViolations {
            showStartInfo("🔒 Ujian terkunci. Hubungi pengawas untuk membukanya.")
        }
        updateViolationUI()
        playIntroAnimation()
    }

    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { return .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .allButUpsideDown }

    // MARK: - Build UI

    private func makeLabel(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular,
                           color: UIColor = .white, align: NSTextAlignment = .center) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.textAlignment = align
        l.numberOfLines = 0
        return l
    }

    private func pin(_ v: UIView, to other: UIView, inset: CGFloat = 0) {
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: other.topAnchor, constant: inset),
            v.leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: inset),
            v.trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -inset),
            v.bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -inset)
        ])
    }

    private func buildStart() {
        view.addSubview(bgView)
        pin(bgView, to: view)

        startScroll.alwaysBounceVertical = false
        startScroll.contentInsetAdjustmentBehavior = .never
        view.addSubview(startScroll)
        pin(startScroll, to: view)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        startScroll.addSubview(content)
        let eqHeight = content.heightAnchor.constraint(equalTo: startScroll.frameLayoutGuide.heightAnchor)
        eqHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: startScroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: startScroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: startScroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: startScroll.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: startScroll.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: startScroll.frameLayoutGuide.heightAnchor),
            eqHeight
        ])

        logoView.contentMode = .scaleAspectFit
        logoView.heightAnchor.constraint(equalToConstant: 230).isActive = true

        let title = makeLabel("IKHLAS LOCK", size: 26, weight: .bold)
        let subtitle = makeLabel("ILOK • CBT SPENNEMA • SMP Negeri 45 Surabaya", size: 13,
                                 color: UIColor(hex: 0x9DB4FF))

        cardView.backgroundColor = UIColor(hex: 0x1A2160, alpha: 0.45)
        cardView.layer.cornerRadius = 20
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor(hex: 0x4C5BD4, alpha: 0.5).cgColor
        let rulesTitle = makeLabel("🛡  Tata Tertib Ujian", size: 16, weight: .bold, align: .left)
        let rules = makeLabel("• Ujian hanya bisa dikerjakan lewat aplikasi ini.\n• Aplikasi lain tidak boleh dibuka selama ujian.\n• Screenshot dan rekam layar dideteksi dan dicatat.\n• Menyalin dan menempel teks dinonaktifkan.\n• Keluar dari layar ujian dicatat sebagai pelanggaran.\n• 3 pelanggaran akan mengunci ujian sampai pengawas membukanya.",
                              size: 13.5, color: UIColor(hex: 0xD5DEFF), align: .left)
        let cardStack = UIStackView(arrangedSubviews: [rulesTitle, rules])
        cardStack.axis = .vertical
        cardStack.spacing = 12
        cardView.addSubview(cardStack)
        pin(cardStack, to: cardView, inset: 20)

        lblStartInfo.font = UIFont.systemFont(ofSize: 13)
        lblStartInfo.textColor = UIColor(hex: 0xFDA4AF)
        lblStartInfo.textAlignment = .center
        lblStartInfo.numberOfLines = 0
        lblStartInfo.isHidden = true

        btnStart.setTitle("MULAI UJIAN", for: .normal)
        btnStart.heightAnchor.constraint(equalToConstant: 52).isActive = true
        btnStart.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        lblDevice.font = UIFont.systemFont(ofSize: 11)
        lblDevice.textColor = UIColor(hex: 0x6F7DB8)
        lblDevice.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [logoView, title, subtitle, cardView, lblStartInfo, btnStart, lblDevice])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(22, after: subtitle)
        stack.setCustomSpacing(22, after: cardView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let maxW = stack.widthAnchor.constraint(lessThanOrEqualToConstant: 480)
        let fillW = stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24)
        fillW.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            maxW, fillW
        ])
    }

    private func buildExam() {
        examContainer.backgroundColor = UIColor(hex: 0x0A0F2C)
        examContainer.isHidden = true
        view.addSubview(examContainer)
        pin(examContainer, to: view)

        // Bilah atas
        header.translatesAutoresizingMaskIntoConstraints = false
        examContainer.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: examContainer.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: examContainer.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 34)
        ])

        // Ketuk 5x untuk membuka dialog PIN pengawas
        btnHeaderLogo.setImage(UIImage(named: "logo"), for: .normal)
        btnHeaderLogo.imageView?.contentMode = .scaleAspectFit
        btnHeaderLogo.addTarget(self, action: #selector(tapLogo), for: .touchUpInside)
        btnHeaderLogo.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(btnHeaderLogo)

        let lblTitle = makeLabel("🔒 ILOK • Ujian Aman", size: 12, weight: .bold,
                                 color: UIColor(hex: 0xE6ECFF), align: .left)
        lblTitle.numberOfLines = 1
        lblTitle.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(lblTitle)

        lblViolation.font = UIFont.systemFont(ofSize: 11)
        lblViolation.textColor = .white
        lblViolation.layer.cornerRadius = 10
        lblViolation.clipsToBounds = true
        lblViolation.translatesAutoresizingMaskIntoConstraints = false
        lblViolation.setContentCompressionResistancePriority(.required, for: .horizontal)
        header.addSubview(lblViolation)

        NSLayoutConstraint.activate([
            btnHeaderLogo.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            btnHeaderLogo.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            btnHeaderLogo.widthAnchor.constraint(equalToConstant: 28),
            btnHeaderLogo.heightAnchor.constraint(equalToConstant: 28),
            lblTitle.leadingAnchor.constraint(equalTo: btnHeaderLogo.trailingAnchor, constant: 8),
            lblTitle.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            lblTitle.trailingAnchor.constraint(lessThanOrEqualTo: lblViolation.leadingAnchor, constant: -8),
            lblViolation.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            lblViolation.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        // WebView
        examContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: examContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: examContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // Progress
        progressView.progressTintColor = UIColor(hex: 0x3B82F6)
        progressView.trackTintColor = .clear
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        examContainer.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: webView.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 3)
        ])

        // Banner peringatan
        banner.insets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        banner.font = UIFont.boldSystemFont(ofSize: 13)
        banner.textColor = .white
        banner.numberOfLines = 0
        banner.backgroundColor = UIColor(hex: 0xE11D48)
        banner.layer.cornerRadius = 12
        banner.clipsToBounds = true
        banner.isHidden = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        examContainer.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            banner.leadingAnchor.constraint(equalTo: examContainer.leadingAnchor, constant: 12),
            banner.trailingAnchor.constraint(equalTo: examContainer.trailingAnchor, constant: -12)
        ])

        // Halaman error / tidak ada koneksi
        errorView.backgroundColor = UIColor(hex: 0x141B4D)
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false
        examContainer.addSubview(errorView)
        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: webView.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
        ])
        let errLogo = UIImageView(image: UIImage(named: "logo"))
        errLogo.contentMode = .scaleAspectFit
        errLogo.heightAnchor.constraint(equalToConstant: 130).isActive = true
        let errTitle = makeLabel("Tidak dapat terhubung", size: 18, weight: .bold)
        lblError.font = UIFont.systemFont(ofSize: 13)
        lblError.textColor = UIColor(hex: 0xB8C6FF)
        lblError.textAlignment = .center
        lblError.numberOfLines = 0
        lblError.text = "Periksa koneksi internet Anda."
        btnRetry.setTitle("COBA LAGI", for: .normal)
        btnRetry.heightAnchor.constraint(equalToConstant: 48).isActive = true
        btnRetry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        let errStack = UIStackView(arrangedSubviews: [errLogo, errTitle, lblError, btnRetry])
        errStack.axis = .vertical
        errStack.spacing = 12
        errStack.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errStack)
        NSLayoutConstraint.activate([
            errStack.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            errStack.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 32),
            errStack.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -32)
        ])
    }

    private func buildLock() {
        lockView.isHidden = true
        view.addSubview(lockView)
        pin(lockView, to: view)

        let icon = makeLabel("🔒", size: 48)
        lblLockTitle.font = UIFont.boldSystemFont(ofSize: 22)
        lblLockTitle.textColor = .white
        lblLockTitle.textAlignment = .center
        lblLockMsg.font = UIFont.systemFont(ofSize: 14)
        lblLockMsg.textColor = UIColor(hex: 0xB8C6FF)
        lblLockMsg.textAlignment = .center
        lblLockMsg.numberOfLines = 0

        pinField.backgroundColor = UIColor(hex: 0x1A2160)
        pinField.textColor = .white
        pinField.font = UIFont.systemFont(ofSize: 18)
        pinField.textAlignment = .center
        pinField.isSecureTextEntry = true
        pinField.keyboardType = .numberPad
        pinField.layer.cornerRadius = 14
        pinField.layer.borderWidth = 1
        pinField.layer.borderColor = UIColor(hex: 0x4C5BD4).cgColor
        pinField.attributedPlaceholder = NSAttributedString(
            string: "PIN pengawas",
            attributes: [.foregroundColor: UIColor(hex: 0x7080C0)])
        pinField.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let tb = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        tb.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                    UIBarButtonItem(title: "Selesai", style: .done, target: self, action: #selector(submitPin))]
        pinField.inputAccessoryView = tb

        lblPinError.font = UIFont.systemFont(ofSize: 13)
        lblPinError.textColor = UIColor(hex: 0xFDA4AF)
        lblPinError.textAlignment = .center
        lblPinError.numberOfLines = 0
        lblPinError.text = "PIN salah"
        lblPinError.alpha = 0

        btnUnlock.heightAnchor.constraint(equalToConstant: 50).isActive = true
        btnUnlock.addTarget(self, action: #selector(submitPin), for: .touchUpInside)

        btnCancel.setTitle("BATAL", for: .normal)
        btnCancel.setTitleColor(UIColor(hex: 0xC7D2FE), for: .normal)
        btnCancel.layer.cornerRadius = 23
        btnCancel.layer.borderWidth = 1
        btnCancel.layer.borderColor = UIColor(hex: 0x6670A8).cgColor
        btnCancel.heightAnchor.constraint(equalToConstant: 46).isActive = true
        btnCancel.addTarget(self, action: #selector(cancelOverlayTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, lblLockTitle, lblLockMsg, pinField, lblPinError, btnUnlock, btnCancel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(22, after: lblLockMsg)
        stack.translatesAutoresizingMaskIntoConstraints = false
        lockView.addSubview(stack)
        let w = stack.widthAnchor.constraint(equalToConstant: 320)
        w.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: lockView.centerXAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 36),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: lockView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: lockView.trailingAnchor, constant: -32),
            w
        ])
    }

    private func buildPrivacyCover() {
        privacyCover.backgroundColor = UIColor(hex: 0x0A0F2C)
        privacyCover.isHidden = true
        view.addSubview(privacyCover)
        pin(privacyCover, to: view)

        let img = UIImageView(image: UIImage(named: "logo"))
        img.contentMode = .scaleAspectFit
        img.heightAnchor.constraint(equalToConstant: 200).isActive = true
        lblCover.font = UIFont.boldSystemFont(ofSize: 16)
        lblCover.textColor = .white
        lblCover.textAlignment = .center
        lblCover.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [img, lblCover])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        privacyCover.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: privacyCover.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: privacyCover.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: privacyCover.trailingAnchor, constant: -32)
        ])
    }

    private func playIntroAnimation() {
        logoView.alpha = 0
        logoView.transform = CGAffineTransform(translationX: 0, y: -30)
        cardView.alpha = 0
        btnStart.alpha = 0
        UIView.animate(withDuration: 0.7) {
            self.logoView.alpha = 1
            self.logoView.transform = .identity
        }
        UIView.animate(withDuration: 0.6, delay: 0.25, options: []) { self.cardView.alpha = 1 }
        UIView.animate(withDuration: 0.5, delay: 0.55, options: []) { self.btnStart.alpha = 1 }
    }

    // MARK: - Anti-curang (pengamat sistem)

    private func registerObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(willResignActive),
                       name: UIApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(didBecomeActive),
                       name: UIApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(screenshotTaken),
                       name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        nc.addObserver(self, selector: #selector(capturedChanged),
                       name: UIScreen.capturedDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(externalScreenConnected),
                       name: UIScreen.didConnectNotification, object: nil)
        nc.addObserver(self, selector: #selector(guidedAccessChanged),
                       name: UIAccessibility.guidedAccessStatusDidChangeNotification, object: nil)
    }

    /// Meninggalkan aplikasi: tombol Home, panel notifikasi, Control Center, app switcher, telepon masuk.
    @objc private func willResignActive() {
        guard examActive else { return }
        showCover("ILOK • Ujian Aman")  // sembunyikan isi ujian di app switcher
        if Date() < graceUntil { return }
        if !awayCounted {
            awayCounted = true
            flagViolation("Anda meninggalkan layar ujian.")
        }
    }

    @objc private func didBecomeActive() {
        hideCover()
        guard examActive else { return }
        clearClipboard()
        updateCaptureState()
        if awayCounted {
            awayCounted = false
            afterViolation()
        }
    }

    /// iOS tidak bisa memblokir screenshot, tetapi bisa mendeteksinya.
    @objc private func screenshotTaken() {
        guard examActive else { return }
        flagViolation("Screenshot terdeteksi.")
        afterViolation()
    }

    @objc private func capturedChanged() { updateCaptureState() }

    @objc private func externalScreenConnected() {
        guard examActive else { return }
        flagViolation("Layar eksternal / AirPlay terdeteksi.")
        afterViolation()
    }

    @objc private func guidedAccessChanged() {
        guard examActive, Config.requireGuidedAccess, !UIAccessibility.isGuidedAccessEnabled else { return }
        flagViolation("Guided Access dimatikan.")
        afterViolation()
    }

    private func updateCaptureState() {
        if examActive && UIScreen.main.isCaptured {
            showCover("Perekaman layar / mirroring terdeteksi.\nHentikan untuk melanjutkan ujian.")
            if !captureFlagged {
                captureFlagged = true
                flagViolation("Perekaman layar / mirroring terdeteksi.")
                afterViolation()
            }
        } else {
            captureFlagged = false
            hideCover()
        }
    }

    private func showCover(_ message: String) {
        lblCover.text = message
        privacyCover.isHidden = false
        view.bringSubviewToFront(privacyCover)
    }

    private func hideCover() {
        if examActive && UIScreen.main.isCaptured { return }
        if UIApplication.shared.applicationState != .active { return }
        privacyCover.isHidden = true
    }

    private func clearClipboard() {
        UIPasteboard.general.items = []
    }

    // MARK: - Pelanggaran

    private func flagViolation(_ msg: String) {
        violations += 1
        updateViolationUI()
        applyUA()
        pendingMsg = "⚠ Pelanggaran \(violations)/\(Config.maxViolations): \(msg)"
    }

    private func afterViolation() {
        guard let msg = pendingMsg else { return }
        pendingMsg = nil
        if violations >= Config.maxViolations {
            showOverlay(.unlock, cancelable: false)
        } else {
            showBanner(msg)
        }
    }

    private func updateViolationUI() {
        lblViolation.text = "Pelanggaran \(violations)/\(Config.maxViolations)"
        lblViolation.backgroundColor = violations > 0 ? UIColor(hex: 0xE11D48) : UIColor(white: 1, alpha: 0.2)
    }

    private func showBanner(_ msg: String) {
        banner.text = msg
        banner.isHidden = false
        examContainer.bringSubviewToFront(banner)
        bannerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.banner.isHidden = true }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func showStartInfo(_ msg: String) {
        lblStartInfo.text = msg
        lblStartInfo.isHidden = false
    }

    // MARK: - Alur ujian

    @objc private func startTapped() {
        if violations >= Config.maxViolations {
            showOverlay(.unlock, cancelable: true)
            return
        }
        if let problem = preflight() {
            showStartInfo("⛔ " + problem)
            return
        }
        startExam()
    }

    /// Pemeriksaan keamanan perangkat sebelum ujian dimulai.
    private func preflight() -> String? {
        if Config.blockJailbreak && Security.isJailbroken {
            return "Perangkat jailbreak tidak diizinkan untuk ujian."
        }
        if UIScreen.main.isCaptured || UIScreen.screens.count > 1 {
            return "Perekaman layar / mirroring terdeteksi. Hentikan dulu, lalu coba lagi."
        }
        if Config.requireGuidedAccess && !UIAccessibility.isGuidedAccessEnabled {
            return "Aktifkan Akses Terpandu (Guided Access): Pengaturan > Aksesibilitas > Akses Terpandu, lalu klik tiga kali tombol samping/Home di layar ini."
        }
        return nil
    }

    private func startExam() {
        examActive = true
        awayCounted = false
        defaults.set(true, forKey: "inExam")
        graceUntil = Date().addingTimeInterval(2)
        lblStartInfo.isHidden = true
        startScroll.isHidden = true
        examContainer.isHidden = false
        UIApplication.shared.isIdleTimerDisabled = true
        clearClipboard()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        // Hanya berhasil pada perangkat terawasi (MDM); diabaikan jika tidak diizinkan.
        UIAccessibility.requestGuidedAccessSession(enabled: true) { _ in }
        uaTimer?.invalidate()
        uaTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.applyUA() }
        loadExam()
    }

    private func exitExam() {
        examActive = false
        defaults.set(false, forKey: "inExam")
        violations = 0
        updateViolationUI()
        uaTimer?.invalidate()
        uaTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        UIAccessibility.requestGuidedAccessSession(enabled: false) { _ in }
        // Hapus sesi, cookie, dan cache agar siswa berikutnya tidak masuk ke akun yang sama.
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) { }
        webView.loadHTMLString("", baseURL: nil)
        hasError = false
        errorView.isHidden = true
        examContainer.isHidden = true
        startScroll.isHidden = false
        lblStartInfo.isHidden = true
    }

    private func loadExam() {
        if baseUA != nil {
            applyUA()
            loadURL()
            return
        }
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
            guard let self = self else { return }
            self.baseUA = (result as? String)
                ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 13_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
            self.applyUA()
            self.loadURL()
        }
    }

    private func loadURL() {
        guard let url = URL(string: Config.examURL) else { return }
        webView.load(URLRequest(url: url))
    }

    private func applyUA() {
        guard let base = baseUA else { return }
        webView.customUserAgent = Security.userAgent(base: base, violations: violations)
    }

    @objc private func retryTapped() {
        hasError = false
        errorView.isHidden = true
        applyUA()
        if webView.backForwardList.currentItem == nil {
            loadURL()
        } else {
            webView.reload()
        }
    }

    // MARK: - Overlay PIN pengawas

    @objc private func tapLogo() {
        let now = Date()
        tapCount = now.timeIntervalSince(lastTap) < 1.5 ? tapCount + 1 : 1
        lastTap = now
        if tapCount >= 5 {
            tapCount = 0
            showOverlay(.exit, cancelable: true)
        }
    }

    private func showOverlay(_ mode: OverlayMode, cancelable: Bool) {
        overlayMode = mode
        switch mode {
        case .unlock:
            lblLockTitle.text = "Ujian Terkunci"
            lblLockMsg.text = "Pelanggaran sudah mencapai batas (\(Config.maxViolations)).\nMinta pengawas memasukkan PIN untuk melanjutkan."
            btnUnlock.setTitle("BUKA KUNCI", for: .normal)
        case .exit:
            lblLockTitle.text = "Keluar dari Ujian"
            lblLockMsg.text = "Khusus pengawas.\nMasukkan PIN untuk keluar dari mode ujian."
            btnUnlock.setTitle("KELUAR", for: .normal)
        }
        btnCancel.isHidden = !cancelable
        pinField.text = ""
        lblPinError.alpha = 0
        lockView.isHidden = false
        view.bringSubviewToFront(lockView)
        view.bringSubviewToFront(privacyCover)
        pinField.becomeFirstResponder()
    }

    private func hideOverlay() {
        pinField.resignFirstResponder()
        lockView.isHidden = true
    }

    @objc private func cancelOverlayTapped() { hideOverlay() }

    private func showPinError(_ msg: String) {
        lblPinError.text = msg
        lblPinError.alpha = 1
    }

    @objc private func submitPin() {
        let now = Date()
        if now < pinBlockedUntil {
            let sec = Int(pinBlockedUntil.timeIntervalSince(now)) + 1
            showPinError("Terlalu banyak percobaan. Coba lagi dalam \(sec) detik.")
            return
        }
        if pinField.text == Config.proctorPin {
            pinFails = 0
            hideOverlay()
            switch overlayMode {
            case .unlock:
                violations = 0
                updateViolationUI()
                lblStartInfo.isHidden = true
                applyUA()
                if !examActive { startExam() }
            case .exit:
                exitExam()
            }
        } else {
            pinFails += 1
            if pinFails % 5 == 0 { pinBlockedUntil = now.addingTimeInterval(30) }
            showPinError("PIN salah")
            pinField.text = ""
        }
    }

    // MARK: - Navigasi

    private func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return false }
        for h in Config.allowedHosts where host == h || host.hasSuffix("." + h) { return true }
        return false
    }

    private func showError(_ msg: String) {
        hasError = true
        lblError.text = msg
        progressView.isHidden = true
        errorView.isHidden = false
    }
}

// MARK: - WKNavigationDelegate

extension MainViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        // Frame di dalam halaman (iframe) dibiarkan, sama seperti versi Android.
        if let target = navigationAction.targetFrame, !target.isMainFrame { decisionHandler(.allow); return }
        // Jendela baru: buka di halaman yang sama bila domain diizinkan.
        if navigationAction.targetFrame == nil {
            if isAllowed(url) { webView.load(navigationAction.request) }
            decisionHandler(.cancel)
            return
        }
        if isAllowed(url) {
            decisionHandler(.allow)
        } else {
            if examActive { showBanner("Halaman ini tidak diizinkan selama ujian.") }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Berkas yang tidak dapat ditampilkan (unduhan) diblokir.
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        hasError = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progressView.isHidden = true
        if !hasError { errorView.isHidden = true }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    private func handleFailure(_ error: Error) {
        let code = (error as NSError).code
        if code == NSURLErrorCancelled { return }
        if code <= -1200 && code >= -1206 {
            showError("Sertifikat keamanan tidak valid.\nPastikan tanggal & jam perangkat benar.")
        } else {
            showError("Periksa koneksi internet Anda lalu coba lagi.")
        }
    }
}

// MARK: - WKUIDelegate (dialog JavaScript)

extension MainViewController: WKUIDelegate {

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        a.addAction(UIAlertAction(title: "Batal", style: .cancel) { _ in completionHandler(false) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
}
