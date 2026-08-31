// chromeless — the browser that isn't there.
//
// A single-file macOS browser with zero chrome: no tabs, no toolbar, no
// address bar — just the page, in a bare rounded window. Built on WKWebView
// (the Safari engine). Made for clean screenshots and fullscreen video.
//
//   ⌘L  search / open url        ⇧⌘S  snapshot viewport → Desktop
//                              ⌥⇧⌘S  snapshot full page → Desktop
//   ⌘R  reload                   ⌘P   pin window on top
//   ⌘[ ⌘]  back / forward        ⌃⌘F  fullscreen
//   ⌘= ⌘- ⌘0  zoom               ⌘drag  move the window
//
// CLI screenshot mode:
//   chromeless https://example.com --snap out.png --full-page --size 1440x900 --wait 2

import Cocoa
import Security
import WebKit

// MARK: - Passkey capability

// WKWebView performs WebAuthn (passkeys via iCloud Keychain / Touch ID) only for
// apps signed with Apple's restricted web-browser.public-key-credential
// entitlement, which needs an Apple-issued provisioning profile — macOS kills
// ad-hoc builds that claim it. So: if this build carries the entitlement,
// passkeys just work; if not, hide the WebAuthn API so sites feature-detect the
// absence and offer their fallback sign-in (password, phone prompt) instead of
// a passkey ceremony that is guaranteed to fail. See README for enabling it.
let hasPasskeyEntitlement: Bool = {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let value = SecTaskCopyValueForEntitlement(
        task, "com.apple.developer.web-browser.public-key-credential" as CFString, nil)
    return (value as? Bool) == true
}()

// MARK: - URL smarts

func smartURL(_ input: String) -> URL? {
    let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return nil }
    if t.hasPrefix("/") || t.hasPrefix("~") {
        let path = (t as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
    }
    if t.contains("://") { return URL(string: t) }
    let lower = t.lowercased()
    for host in ["localhost", "127.0.0.1", "0.0.0.0", "[::1]"] where lower.hasPrefix(host) {
        return URL(string: "http://" + t)
    }
    if !t.contains(" "), t.contains(".") { return URL(string: "https://" + t) }
    let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
    return URL(string: "https://www.google.com/search?q=" + q)
}

// MARK: - Launch options

struct SnapJob {
    let path: String
    let wait: TimeInterval
    let fullPage: Bool
}

struct LaunchOptions {
    var url: URL? = nil
    var snap: SnapJob? = nil
    var size: NSSize? = nil
    var fullPage = false
}

func parseLaunchOptions() -> LaunchOptions {
    var opts = LaunchOptions()
    var snapPath: String? = nil
    var wait: TimeInterval = 1.0
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        let a = args[i]
        switch a {
        case "--help", "-h":
            print("""
            chromeless — the browser that isn't there

            usage: chromeless [url] [options]
              --snap <path>     load the page, save a PNG of it, and quit
              --full-page      capture the full vertical page with --snap
              --size <WxH>      window size in points (e.g. 1440x900)
              --wait <seconds>  extra settle time before --snap (default 1.0)

            examples:
              chromeless youtube.com
              chromeless localhost:3000 --snap shot.png --full-page --size 1280x800
            """)
            exit(0)
        case "--snap":
            i += 1
            if i < args.count { snapPath = args[i] }
        case "--full-page":
            opts.fullPage = true
        case "--size":
            i += 1
            if i < args.count {
                let parts = args[i].lowercased().split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 { opts.size = NSSize(width: parts[0], height: parts[1]) }
            }
        case "--wait":
            i += 1
            if i < args.count { wait = Double(args[i]) ?? 1.0 }
        default:
            if a.hasPrefix("-") {
                fputs("chromeless: ignoring unknown option \(a)\n", stderr)
            } else if let u = smartURL(a) {
                opts.url = u
            }
        }
        i += 1
    }
    if let p = snapPath {
        let abs = p.hasPrefix("/") ? p : FileManager.default.currentDirectoryPath + "/" + p
        opts.snap = SnapJob(path: abs, wait: wait, fullPage: opts.fullPage)
    }
    return opts
}

let launchOptions = parseLaunchOptions()

// MARK: - Start page

let startPageHTML = """
<!doctype html>
<html><head><meta charset="utf-8"><title>chromeless</title>
<style>
  html, body { height: 100%; margin: 0; }
  body { background: #0a0a0e; color: #e8e8ee; font: 15px/1.6 -apple-system, system-ui;
         display: flex; align-items: center; justify-content: center;
         -webkit-user-select: none; cursor: default; }
  main { text-align: center; max-width: 680px; padding: 48px; animation: in .6s ease-out; }
  @keyframes in { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; } }
  h1 { font-size: 46px; font-weight: 650; letter-spacing: -.02em; margin: 0 0 6px; color: #fff; }
  p.tag { color: #85858f; margin: 0 0 46px; font-size: 16px; }
  .keys { display: grid; grid-template-columns: auto auto; gap: 11px 22px;
          justify-content: center; text-align: left; font-size: 13.5px; color: #b9b9c4; }
  .k { text-align: right; }
  kbd { font: 600 12px ui-monospace, "SF Mono", monospace; background: #1b1b22;
        border: 1px solid #2c2c36; border-bottom-width: 2px; border-radius: 6px;
        padding: 2.5px 8px; color: #e8e8ee; white-space: nowrap; }
  footer { margin-top: 48px; color: #55555e; font-size: 12px; }
</style></head>
<body><main>
  <h1>chromeless</h1>
  <p class="tag">the browser that isn&rsquo;t there</p>
  <div class="keys">
    <div class="k"><kbd>&#8984; L</kbd></div>       <div>search or enter a url</div>
    <div class="k"><kbd>&#8984; drag</kbd></div>    <div>move the window</div>
    <div class="k"><kbd>&#8963;&#8984; F</kbd></div><div>fullscreen</div>
    <div class="k"><kbd>&#8679;&#8984; S</kbd></div><div>snapshot the viewport &rarr; desktop</div>
    <div class="k"><kbd>&#8997;&#8679;&#8984; S</kbd></div><div>snapshot the full page &rarr; desktop</div>
    <div class="k"><kbd>&#8984; P</kbd></div>       <div>pin on top of every window</div>
    <div class="k"><kbd>&#8984; [</kbd> <kbd>&#8984; ]</kbd></div><div>back / forward</div>
    <div class="k"><kbd>esc</kbd></div>             <div>bail out &mdash; back to this page</div>
    <div class="k"><kbd>&#8984; =</kbd> <kbd>&#8984; &minus;</kbd> <kbd>&#8984; 0</kbd></div><div>zoom</div>
    <div class="k"><kbd>&#8679;&#8984; C</kbd></div><div>copy current url</div>
  </div>
  <footer>&#8984;N new window &nbsp;&middot;&nbsp; &#8984;R reload &nbsp;&middot;&nbsp; &#8984;W close</footer>
</main></body></html>
"""

// MARK: - Views

final class BrowserWebView: WKWebView {
    // Bare Esc escapes back to the start page — unless fullscreen needs it,
    // or the ⌘L HUD is open (its field is first responder and handles Esc itself).
    var onEscape: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, // Esc
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           window?.styleMask.contains(.fullScreen) != true,
           fullscreenState == .notInFullscreen,
           onEscape?() == true {
            return
        }
        super.keyDown(with: event)
    }

    // ⌘-drag anywhere moves the window; mouse buttons 4/5 go back/forward.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            window?.performDrag(with: event)
            return
        }
        super.mouseDown(with: event)
    }
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 3, canGoBack { goBack(); return }
        if event.buttonNumber == 4, canGoForward { goForward(); return }
        super.otherMouseUp(with: event)
    }
}

final class LayoutReportingView: NSView {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

struct ManagedPageScrollInfo {
    let elementID: String
    let viewportHeight: Double
    let contentTop: Double
    let contentHeight: Double
    let maximumScroll: Double
    let originalScroll: Double
}

enum SnapshotCaptureError: LocalizedError {
    case alreadyInProgress
    case invalidPageMetrics
    case imageTooLarge(Int, Int)
    case couldNotCreateImage

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "another snapshot is already in progress"
        case .invalidPageMetrics:
            return "could not measure the page"
        case let .imageTooLarge(width, height):
            return "page is too large to capture safely (\(width)x\(height) px)"
        case .couldNotCreateImage:
            return "could not create the snapshot image"
        }
    }
}

// MARK: - Browser window

final class BrowserWindowController: NSWindowController, NSWindowDelegate,
    WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate, NSMenuItemValidation {

    let webView: BrowserWebView
    private let progressBar = NSView()
    private let hud = NSVisualEffectView()
    private let hudField = NSTextField()
    private let toastView = NSVisualEffectView()
    private let toastLabel = NSTextField(labelWithString: "")
    private var observations: [NSKeyValueObservation] = []
    private var mouseMonitor: Any?
    private var snapJob: SnapJob?
    private var toastHide: DispatchWorkItem?
    private var lastProgress: CGFloat = 0
    private var onStartPage = false
    private var snapshotInProgress = false
    var onClose: (() -> Void)?

    init(url: URL?, size: NSSize?, snap: SnapJob?, isPrimary: Bool) {
        let conf = WKWebViewConfiguration()
        conf.preferences.isElementFullscreenEnabled = true
        conf.mediaTypesRequiringUserActionForPlayback = []
        conf.allowsAirPlayForMediaPlayback = true
        conf.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        if !hasPasskeyEntitlement {
            let hideWebAuthn = WKUserScript(
                source: """
                (function () {
                  try {
                    delete window.PublicKeyCredential;
                    delete window.AuthenticatorResponse;
                    delete window.AuthenticatorAttestationResponse;
                    delete window.AuthenticatorAssertionResponse;
                  } catch (e) {}
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            conf.userContentController.addUserScript(hideWebAuthn)
        }
        webView = BrowserWebView(frame: .zero, configuration: conf)
        snapJob = snap

        let contentSize = size ?? NSSize(width: 1160, height: 760)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)

        window.title = "Chromeless"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 320, height: 220)
        window.backgroundColor = NSColor(calibratedWhite: 0.04, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.acceptsMouseMovedEvents = true
        window.delegate = self
        setTrafficLights(visible: false)

        let container = LayoutReportingView(frame: NSRect(origin: .zero, size: contentSize))
        container.onLayout = { [weak self] in self?.layoutOverlays() }
        window.contentView = container

        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        webView.onEscape = { [weak self] in self?.escapeToStart() ?? false }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = NSColor(calibratedWhite: 0.04, alpha: 1)
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        container.addSubview(webView)

        buildOverlays(in: container)
        observeWebView()

        window.center()
        if isPrimary && snap == nil {
            window.setFrameUsingName("ChromelessMain")
            window.setFrameAutosaveName("ChromelessMain")
        } else if let key = NSApp.keyWindow {
            window.setFrameTopLeftPoint(NSPoint(x: key.frame.minX + 30, y: key.frame.maxY - 30))
        }
        if let size { window.setContentSize(size) }

        installMouseMonitor()

        if let url { navigate(to: url) } else { loadStartPage() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Chrome (what little there is)

    private func setTrafficLights(visible: Bool) {
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = !visible
        }
    }

    private var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }

    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .mouseMoved {
                // Reveal the traffic lights only when hovering the top-left corner.
                guard let contentView = self.window?.contentView else { return event }
                let p = event.locationInWindow
                let nearCorner = p.y > contentView.bounds.height - 44 && p.x < 96
                self.setTrafficLights(visible: self.isFullScreen || nearCorner)
            } else if !self.hud.isHidden {
                let p = self.window!.contentView!.convert(event.locationInWindow, from: nil)
                if !self.hud.frame.contains(p) { self.hideHUD() }
            }
            return event
        }
    }

    private func buildOverlays(in container: NSView) {
        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        progressBar.alphaValue = 0
        container.addSubview(progressBar)

        hud.material = .hudWindow
        hud.blendingMode = .withinWindow
        hud.state = .active
        hud.wantsLayer = true
        hud.layer?.cornerRadius = 26
        hud.layer?.cornerCurve = .continuous
        hud.layer?.masksToBounds = true
        hud.layer?.borderWidth = 1
        hud.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        hud.isHidden = true
        hud.alphaValue = 0
        hudField.isBezeled = false
        hudField.isBordered = false
        hudField.drawsBackground = false
        hudField.focusRingType = .none
        hudField.font = .systemFont(ofSize: 16)
        hudField.textColor = .labelColor
        hudField.placeholderString = "Search or enter address"
        hudField.usesSingleLineMode = true
        hudField.cell?.isScrollable = true
        hudField.cell?.wraps = false
        hudField.delegate = self
        hud.addSubview(hudField)
        container.addSubview(hud)

        toastView.material = .hudWindow
        toastView.blendingMode = .withinWindow
        toastView.state = .active
        toastView.wantsLayer = true
        toastView.layer?.cornerRadius = 17
        toastView.layer?.cornerCurve = .continuous
        toastView.layer?.masksToBounds = true
        toastView.isHidden = true
        toastView.alphaValue = 0
        toastLabel.font = .systemFont(ofSize: 13, weight: .medium)
        toastLabel.textColor = .labelColor
        toastView.addSubview(toastLabel)
        container.addSubview(toastView)
    }

    private func layoutOverlays() {
        guard let contentView = window?.contentView else { return }
        let b = contentView.bounds
        let hudW = min(620, max(280, b.width - 48))
        let hudH: CGFloat = 52
        hud.frame = NSRect(x: (b.width - hudW) / 2, y: b.height - hudH - 84, width: hudW, height: hudH)
        hudField.frame = NSRect(x: 20, y: (hudH - 22) / 2, width: hudW - 40, height: 22)

        toastLabel.sizeToFit()
        let ts = toastLabel.frame.size
        let tw = ts.width + 32
        let th: CGFloat = 34
        toastView.frame = NSRect(x: (b.width - tw) / 2, y: 28, width: tw, height: th)
        toastLabel.frame = NSRect(x: 16, y: (th - ts.height) / 2, width: ts.width, height: ts.height)

        progressBar.frame = NSRect(x: 0, y: b.height - 2, width: b.width * lastProgress, height: 2)
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                self?.progressChanged(wv.estimatedProgress)
            },
            webView.observe(\.title) { [weak self] wv, _ in
                let t = wv.title ?? ""
                self?.window?.title = t.isEmpty ? "Chromeless" : t
            },
            webView.observe(\.url) { wv, _ in
                if let u = wv.url, u.scheme == "https" || u.scheme == "http" {
                    UserDefaults.standard.set(u.absoluteString, forKey: "LastURL")
                }
            },
        ]
    }

    private func progressChanged(_ progress: Double) {
        lastProgress = CGFloat(progress)
        if let width = window?.contentView?.bounds.width {
            progressBar.frame.size.width = width * lastProgress
        }
        if progress >= 1.0 {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                progressBar.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.lastProgress = 0
                self?.layoutOverlays()
            })
        } else {
            progressBar.alphaValue = 1
        }
    }

    // MARK: Navigation

    func navigate(to url: URL) {
        onStartPage = false
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func loadStartPage() {
        onStartPage = true
        webView.loadHTMLString(startPageHTML, baseURL: nil)
    }

    private func escapeToStart() -> Bool {
        if onStartPage { return false }
        loadStartPage()
        return true
    }

    // MARK: HUD (the ⌘L address bar)

    func showHUD() {
        if let u = webView.url, !onStartPage, u.absoluteString != "about:blank" {
            hudField.stringValue = u.absoluteString
        } else {
            hudField.stringValue = ""
        }
        hud.isHidden = false
        layoutOverlays()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            hud.animator().alphaValue = 1
        }
        hudField.selectText(nil)
    }

    func hideHUD() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.hud.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.hud.isHidden = true
            self.window?.makeFirstResponder(self.webView)
        })
    }

    private func commitHUD() {
        let text = hudField.stringValue
        hideHUD()
        if let url = smartURL(text) { navigate(to: url) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { hideHUD(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { commitHUD(); return true }
        return false
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toastLabel.stringValue = text
        layoutOverlays()
        toastHide?.cancel()
        toastView.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toastView.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                self.toastView.animator().alphaValue = 0
            }, completionHandler: { self.toastView.isHidden = true })
        }
        toastHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: work)
    }

    // MARK: Snapshots

    private func writePNG(from image: NSImage, to path: String) -> (Int, Int)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else { return nil }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return (cg.width, cg.height)
        } catch {
            return nil
        }
    }

    private func takePageSnapshot(fullPage: Bool,
                                  completion: @escaping (NSImage?, Error?) -> Void) {
        guard !snapshotInProgress else {
            completion(nil, SnapshotCaptureError.alreadyInProgress)
            return
        }
        snapshotInProgress = true

        var didFinish = false
        let finish: (NSImage?, Error?) -> Void = { [weak self] image, error in
            guard !didFinish else { return }
            didFinish = true
            self?.snapshotInProgress = false
            completion(image, error)
        }

        guard fullPage else {
            webView.takeSnapshot(with: nil) { image, error in finish(image, error) }
            return
        }

        // WKSnapshotConfiguration only supports rectangles inside the visible
        // view bounds. Capture successive viewports instead, then stitch them
        // without resizing the web view (which would change responsive layouts).
        let metricsScript = """
        (() => {
          const root = document.documentElement;
          const body = document.body;
          const values = [
            root ? root.scrollHeight : 0, root ? root.offsetHeight : 0,
            root ? root.clientHeight : 0, body ? body.scrollHeight : 0,
            body ? body.offsetHeight : 0, body ? body.clientHeight : 0,
            window.innerHeight
          ];
          return {
            height: Math.max(...values),
            viewportHeight: window.innerHeight,
            scrollX: window.scrollX,
            scrollY: window.scrollY,
            flutterView: !!document.querySelector("flutter-view"),
            rootSnap: root ? root.style.scrollSnapType : "",
            bodySnap: body ? body.style.scrollSnapType : ""
          };
        })()
        """

        webView.evaluateJavaScript(metricsScript) { [weak self] value, error in
            guard let self else { return }
            guard error == nil,
                  let metrics = value as? [String: Any],
                  let pageHeight = (metrics["height"] as? NSNumber)?.doubleValue,
                  let viewportHeight = (metrics["viewportHeight"] as? NSNumber)?.doubleValue,
                  let originalX = (metrics["scrollX"] as? NSNumber)?.doubleValue,
                  let originalY = (metrics["scrollY"] as? NSNumber)?.doubleValue,
                  pageHeight.isFinite, viewportHeight.isFinite,
                  pageHeight > 0, viewportHeight > 0
            else {
                finish(nil, error ?? SnapshotCaptureError.invalidPageMetrics)
                return
            }

            // Flutter Web keeps the browser document fixed at one viewport and
            // scrolls inside its rendered scene. Enabling Flutter's semantics
            // exposes that internal scrollable with real dimensions, allowing
            // it to be captured without guessing from canvas pixels.
            if metrics["flutterView"] as? Bool == true,
               pageHeight <= viewportHeight + 1 {
                self.prepareFlutterScrollCapture { info, prepareError in
                    if let prepareError {
                        finish(nil, prepareError)
                    } else if let info {
                        self.takeManagedFullPageSnapshot(info, completion: finish)
                    } else {
                        // A Flutter view with no overflowing semantics scroller
                        // genuinely fits in one viewport.
                        self.webView.takeSnapshot(with: nil) { image, error in
                            finish(image, error)
                        }
                    }
                }
                return
            }

            let rootSnap = metrics["rootSnap"] as? String ?? ""
            let bodySnap = metrics["bodySnap"] as? String ?? ""
            let restoreValues = [rootSnap, bodySnap]
            let restoreJSON = (try? JSONSerialization.data(withJSONObject: restoreValues))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\",\"\"]"

            // Scroll snapping can otherwise move a requested tile and leave gaps.
            self.webView.evaluateJavaScript("""
            (() => {
              if (document.documentElement) document.documentElement.style.scrollSnapType = "none";
              if (document.body) document.body.style.scrollSnapType = "none";
            })()
            """)

            var bitmapContext: CGContext?
            var pixelWidth = 0
            var pixelHeight = 0
            var pixelsPerCSSPoint = 0.0
            let maximumPixelCount = 100_000_000
            let maximumScrollY = max(0, pageHeight - viewportHeight)

            func restorePageAndFinish(_ image: NSImage?, _ captureError: Error?) {
                self.webView.evaluateJavaScript("""
                (() => {
                  const saved = \(restoreJSON);
                  if (document.documentElement) document.documentElement.style.scrollSnapType = saved[0];
                  if (document.body) document.body.style.scrollSnapType = saved[1];
                  window.scrollTo({left: \(originalX), top: \(originalY), behavior: "instant"});
                })()
                """) { _, _ in
                    finish(image, captureError)
                }
            }

            func captureTile(at requestedY: Double) {
                self.webView.evaluateJavaScript("""
                (() => {
                  window.scrollTo({left: \(originalX), top: \(requestedY), behavior: "instant"});
                  return window.scrollY;
                })()
                """) { value, scrollError in
                    guard scrollError == nil, let actualY = (value as? NSNumber)?.doubleValue else {
                        restorePageAndFinish(nil, scrollError ?? SnapshotCaptureError.invalidPageMetrics)
                        return
                    }

                    // Give sticky elements, images, and compositor layers a frame
                    // to settle at their new scroll position before capture.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.webView.takeSnapshot(with: nil) { image, snapshotError in
                            guard let image,
                                  let tile = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                            else {
                                restorePageAndFinish(nil,
                                    snapshotError ?? SnapshotCaptureError.couldNotCreateImage)
                                return
                            }

                            if bitmapContext == nil {
                                pixelWidth = tile.width
                                pixelsPerCSSPoint = Double(tile.height) / viewportHeight
                                pixelHeight = Int(ceil(pageHeight * pixelsPerCSSPoint))
                                guard pixelWidth > 0, pixelHeight > 0,
                                      pixelWidth <= maximumPixelCount / pixelHeight,
                                      let context = CGContext(
                                        data: nil,
                                        width: pixelWidth,
                                        height: pixelHeight,
                                        bitsPerComponent: 8,
                                        bytesPerRow: pixelWidth * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)
                                            ?? CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                                else {
                                    restorePageAndFinish(nil,
                                        SnapshotCaptureError.imageTooLarge(pixelWidth, pixelHeight))
                                    return
                                }
                                bitmapContext = context
                            }

                            guard let context = bitmapContext else {
                                restorePageAndFinish(nil, SnapshotCaptureError.couldNotCreateImage)
                                return
                            }
                            let top = Int(round(actualY * pixelsPerCSSPoint))
                            let destination = CGRect(
                                x: 0,
                                y: pixelHeight - top - tile.height,
                                width: tile.width,
                                height: tile.height)
                            context.draw(tile, in: destination)

                            if actualY >= maximumScrollY - 0.5 {
                                guard let result = context.makeImage() else {
                                    restorePageAndFinish(nil,
                                        SnapshotCaptureError.couldNotCreateImage)
                                    return
                                }
                                let finalImage = NSImage(
                                    cgImage: result,
                                    size: NSSize(width: result.width, height: result.height))
                                restorePageAndFinish(finalImage, nil)
                                return
                            }

                            let nextY = min(actualY + viewportHeight, maximumScrollY)
                            guard nextY > actualY + 0.5 else {
                                restorePageAndFinish(nil, SnapshotCaptureError.invalidPageMetrics)
                                return
                            }
                            captureTile(at: nextY)
                        }
                    }
                }
            }

            captureTile(at: 0)
        }
    }

    private func prepareFlutterScrollCapture(
        completion: @escaping (ManagedPageScrollInfo?, Error?) -> Void
    ) {
        let enableSemanticsScript = """
        (() => {
          if (!document.querySelector("flutter-view")) return false;
          const ready = [...document.querySelectorAll("flt-semantics")]
            .some(el => el.scrollHeight > el.clientHeight + 1);
          if (!ready) document.querySelector("flt-semantics-placeholder")?.click();
          return true;
        })()
        """

        webView.evaluateJavaScript(enableSemanticsScript) { [weak self] value, error in
            guard let self else { return }
            guard error == nil, value as? Bool == true else {
                completion(nil, error ?? SnapshotCaptureError.invalidPageMetrics)
                return
            }

            let findScrollerScript = """
            (() => {
              const candidates = [...document.querySelectorAll("flt-semantics")]
                .map(el => {
                  const rect = el.getBoundingClientRect();
                  return {
                    el,
                    rect,
                    range: el.scrollHeight - el.clientHeight,
                    overflow: getComputedStyle(el).overflowY
                  };
                })
                .filter(item => item.range > 1 && item.rect.width > 0 &&
                  (item.overflow === "auto" || item.overflow === "scroll"))
                .sort((a, b) => b.range - a.range);
              const item = candidates[0];
              if (!item) return null;
              if (!item.el.id) item.el.id = "chromeless-managed-scroll";
              let style = document.getElementById("chromeless-snapshot-scrollbars");
              if (!style) {
                style = document.createElement("style");
                style.id = "chromeless-snapshot-scrollbars";
                style.textContent = `
                  flt-semantics::-webkit-scrollbar {
                    display: none !important;
                    width: 0 !important;
                    height: 0 !important;
                  }
                `;
                document.head.appendChild(style);
              }
              return {
                id: item.el.id,
                viewportHeight: window.innerHeight,
                contentTop: Math.max(0, item.rect.top),
                contentHeight: item.el.clientHeight,
                maximumScroll: item.range,
                originalScroll: item.el.scrollTop
              };
            })()
            """

            func pollForScroller(_ attempt: Int) {
                self.webView.evaluateJavaScript(findScrollerScript) { value, error in
                    if let error {
                        completion(nil, error)
                        return
                    }
                    if let values = value as? [String: Any],
                       let id = values["id"] as? String,
                       let viewportHeight = (values["viewportHeight"] as? NSNumber)?.doubleValue,
                       let contentTop = (values["contentTop"] as? NSNumber)?.doubleValue,
                       let contentHeight = (values["contentHeight"] as? NSNumber)?.doubleValue,
                       let maximumScroll = (values["maximumScroll"] as? NSNumber)?.doubleValue,
                       let originalScroll = (values["originalScroll"] as? NSNumber)?.doubleValue,
                       viewportHeight > 0, contentHeight > 0, maximumScroll > 0 {
                        completion(ManagedPageScrollInfo(
                            elementID: id,
                            viewportHeight: viewportHeight,
                            contentTop: contentTop,
                            contentHeight: contentHeight,
                            maximumScroll: maximumScroll,
                            originalScroll: originalScroll), nil)
                        return
                    }
                    guard attempt < 20 else {
                        completion(nil, nil)
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        pollForScroller(attempt + 1)
                    }
                }
            }

            pollForScroller(0)
        }
    }

    private func takeManagedFullPageSnapshot(
        _ info: ManagedPageScrollInfo,
        completion: @escaping (NSImage?, Error?) -> Void
    ) {
        let encodedID = (try? JSONEncoder().encode(info.elementID))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let maximumPixelCount = 100_000_000
        let bottomFixedTop = min(info.viewportHeight, info.contentTop + info.contentHeight)
        let bottomFixedHeight = max(0, info.viewportHeight - bottomFixedTop)
        let pageHeight = info.viewportHeight + info.maximumScroll
        var bitmapContext: CGContext?
        var pixelHeight = 0
        var pixelsPerCSSPoint = 0.0

        func setScroll(_ requested: Double, then action: @escaping (Double, Error?) -> Void) {
            webView.evaluateJavaScript("""
            (() => {
              const el = document.getElementById(\(encodedID));
              if (!el) return null;
              el.scrollTop = \(requested);
              el.dispatchEvent(new Event("scroll"));
              return el.scrollTop;
            })()
            """) { value, error in
                guard error == nil, let actual = (value as? NSNumber)?.doubleValue else {
                    action(0, error ?? SnapshotCaptureError.invalidPageMetrics)
                    return
                }
                // Flutter's desktop scroll indicator fades shortly after a
                // programmatic scroll. Wait for it so it is not baked into
                // every stitched tile.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    action(actual, nil)
                }
            }
        }

        func restoreAndFinish(_ image: NSImage?, _ error: Error?) {
            setScroll(info.originalScroll) { _, _ in
                self.webView.evaluateJavaScript(
                    "document.getElementById('chromeless-snapshot-scrollbars')?.remove()"
                ) { _, _ in
                    completion(image, error)
                }
            }
        }

        func drawRegion(from tile: CGImage, sourceTop: Double, sourceHeight: Double,
                        outputTop: Double) -> Bool {
            guard let context = bitmapContext, sourceHeight > 0 else { return sourceHeight <= 0 }
            let sourceY = max(0, Int(round(sourceTop * pixelsPerCSSPoint)))
            let requestedHeight = Int(round(sourceHeight * pixelsPerCSSPoint))
            let sourcePixelHeight = min(requestedHeight, tile.height - sourceY)
            guard sourcePixelHeight > 0,
                  let cropped = tile.cropping(to: CGRect(
                    x: 0, y: sourceY, width: tile.width, height: sourcePixelHeight))
            else { return false }
            let outputY = Int(round(outputTop * pixelsPerCSSPoint))
            context.draw(cropped, in: CGRect(
                x: 0,
                y: pixelHeight - outputY - cropped.height,
                width: cropped.width,
                height: cropped.height))
            return true
        }

        func captureTile(at requested: Double) {
            setScroll(requested) { actual, scrollError in
                guard scrollError == nil else {
                    restoreAndFinish(nil, scrollError)
                    return
                }
                self.webView.takeSnapshot(with: nil) { image, snapshotError in
                    guard let image,
                          let tile = image.cgImage(
                            forProposedRect: nil, context: nil, hints: nil)
                    else {
                        restoreAndFinish(nil,
                            snapshotError ?? SnapshotCaptureError.couldNotCreateImage)
                        return
                    }

                    if bitmapContext == nil {
                        pixelsPerCSSPoint = Double(tile.height) / info.viewportHeight
                        pixelHeight = Int(ceil(pageHeight * pixelsPerCSSPoint))
                        let pixelWidth = tile.width
                        guard pixelWidth > 0, pixelHeight > 0,
                              pixelWidth <= maximumPixelCount / pixelHeight,
                              let context = CGContext(
                                data: nil,
                                width: pixelWidth,
                                height: pixelHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: pixelWidth * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)
                                    ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                        else {
                            restoreAndFinish(nil,
                                SnapshotCaptureError.imageTooLarge(pixelWidth, pixelHeight))
                            return
                        }
                        bitmapContext = context
                    }

                    if actual <= 0.5,
                       !drawRegion(from: tile, sourceTop: 0,
                                   sourceHeight: info.contentTop, outputTop: 0) {
                        restoreAndFinish(nil, SnapshotCaptureError.couldNotCreateImage)
                        return
                    }
                    guard drawRegion(
                        from: tile,
                        sourceTop: info.contentTop,
                        sourceHeight: info.contentHeight,
                        outputTop: info.contentTop + actual)
                    else {
                        restoreAndFinish(nil, SnapshotCaptureError.couldNotCreateImage)
                        return
                    }

                    if actual >= info.maximumScroll - 0.5 {
                        guard drawRegion(
                            from: tile,
                            sourceTop: bottomFixedTop,
                            sourceHeight: bottomFixedHeight,
                            outputTop: info.contentTop + info.contentHeight + info.maximumScroll),
                              let result = bitmapContext?.makeImage()
                        else {
                            restoreAndFinish(nil, SnapshotCaptureError.couldNotCreateImage)
                            return
                        }
                        let finalImage = NSImage(
                            cgImage: result,
                            size: NSSize(width: result.width, height: result.height))
                        restoreAndFinish(finalImage, nil)
                        return
                    }

                    let next = min(actual + info.contentHeight, info.maximumScroll)
                    guard next > actual + 0.5 else {
                        restoreAndFinish(nil, SnapshotCaptureError.invalidPageMetrics)
                        return
                    }
                    captureTile(at: next)
                }
            }
        }

        captureTile(at: 0)
    }

    private func runSnapJob(_ job: SnapJob) {
        DispatchQueue.main.asyncAfter(deadline: .now() + job.wait) { [weak self] in
            guard let self else { exit(3) }
            self.takePageSnapshot(fullPage: job.fullPage) { image, error in
                guard let image, let dims = self.writePNG(from: image, to: job.path) else {
                    fputs("chromeless: snapshot failed: \(error?.localizedDescription ?? "could not write PNG")\n", stderr)
                    exit(3)
                }
                print("saved \(job.path) (\(dims.0)x\(dims.1) px)")
                exit(0)
            }
        }
    }

    // MARK: Menu actions

    @objc func openLocation(_ sender: Any?) { showHUD() }

    @objc func reloadPage(_ sender: Any?) {
        if onStartPage { loadStartPage() } else { webView.reload() }
    }

    @objc func hardReloadPage(_ sender: Any?) {
        if onStartPage { loadStartPage() } else { webView.reloadFromOrigin() }
    }

    @objc func goBackAction(_ sender: Any?) { webView.goBack() }
    @objc func goForwardAction(_ sender: Any?) { webView.goForward() }

    @objc func zoomInPage(_ sender: Any?) { webView.pageZoom = min(webView.pageZoom * 1.1, 5.0) }
    @objc func zoomOutPage(_ sender: Any?) { webView.pageZoom = max(webView.pageZoom / 1.1, 0.25) }
    @objc func resetZoom(_ sender: Any?) { webView.pageZoom = 1.0 }

    @objc func saveSnapshot(_ sender: Any?) {
        saveSnapshotToDesktop(fullPage: false)
    }

    @objc func saveFullPageSnapshot(_ sender: Any?) {
        saveSnapshotToDesktop(fullPage: true)
    }

    private func saveSnapshotToDesktop(fullPage: Bool) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "chromeless \(formatter.string(from: Date())).png"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let path = desktop.appendingPathComponent(name).path
        if fullPage { showToast("Capturing full page…") }
        takePageSnapshot(fullPage: fullPage) { [weak self] image, error in
            guard let self else { return }
            if let image, self.writePNG(from: image, to: path) != nil {
                self.showToast("Saved “\(name)” to Desktop")
            } else {
                self.showToast(error?.localizedDescription ?? "Snapshot failed")
            }
        }
    }

    @objc func copyPageURL(_ sender: Any?) {
        guard let u = webView.url, u.absoluteString != "about:blank" else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(u.absoluteString, forType: .string)
        showToast("URL copied")
    }

    @objc func togglePin(_ sender: Any?) {
        guard let window else { return }
        let pinned = window.level == .floating
        window.level = pinned ? .normal : .floating
        showToast(pinned ? "Unpinned" : "Pinned on top")
    }

    @objc func showHelpPage(_ sender: Any?) { loadStartPage() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goBackAction(_:)): return webView.canGoBack
        case #selector(goForwardAction(_:)): return webView.canGoForward
        case #selector(copyPageURL(_:)):
            return webView.url != nil && webView.url?.absoluteString != "about:blank"
        case #selector(saveSnapshot(_:)), #selector(saveFullPageSnapshot(_:)):
            return !snapshotInProgress
        case #selector(togglePin(_:)):
            menuItem.state = window?.level == .floating ? .on : .off
            return true
        default: return true
        }
    }

    // MARK: NSWindowDelegate

    func windowDidEnterFullScreen(_ notification: Notification) { setTrafficLights(visible: true) }
    func windowDidExitFullScreen(_ notification: Notification) { setTrafficLights(visible: false) }

    func windowWillClose(_ notification: Notification) {
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
        mouseMonitor = nil
        observations.removeAll()
        onClose?()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let u = webView.url?.absoluteString
        if u != nil && u != "about:blank" { onStartPage = false }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let job = snapJob {
            snapJob = nil
            runSnapJob(job)
        } else if onStartPage {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.onStartPage, self.window?.isKeyWindow == true else { return }
                self.showHUD()
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    private func handleLoadError(_ error: Error) {
        let e = error as NSError
        // Ignore cancelled loads and "frame load interrupted" (downloads, redirects).
        if e.code == NSURLErrorCancelled || e.code == 102 { return }
        if launchOptions.snap != nil {
            fputs("chromeless: load failed: \(e.localizedDescription)\n", stderr)
            exit(1)
        }
        showToast("Couldn’t load — \(e.localizedDescription)")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Hand non-web schemes (mailto:, facetime:, app links…) to the system.
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "file", "about", "data", "blob", "javascript"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            showToast("Can’t display this file type")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // No tabs, no popups: target=_blank loads right here.
        if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controllers: [BrowserWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()

        let url: URL? = {
            if let u = launchOptions.url { return u }
            if launchOptions.snap != nil { return nil }
            if let s = UserDefaults.standard.string(forKey: "LastURL") { return URL(string: s) }
            return nil
        }()
        openWindow(url: url, size: launchOptions.size, snap: launchOptions.snap, isPrimary: true)
        NSApp.activate(ignoringOtherApps: true)

        if launchOptions.snap != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                fputs("chromeless: --snap timed out\n", stderr)
                exit(2)
            }
        }
    }

    func openWindow(url: URL?, size: NSSize? = nil, snap: SnapJob? = nil, isPrimary: Bool = false) {
        let controller = BrowserWindowController(url: url, size: size, snap: snap, isPrimary: isPrimary)
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc func newWindow(_ sender: Any?) { openWindow(url: nil) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openWindow(url: url) }
    }

    // MARK: Menu

    private func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Chromeless",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Chromeless", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Chromeless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Chromeless", action: nil, keyEquivalent: "").submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        let newWin = fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        newWin.target = self
        fileMenu.addItem(withTitle: "Open Location…",
                         action: #selector(BrowserWindowController.openLocation(_:)), keyEquivalent: "l")
        fileMenu.addItem(.separator())
        let snap = fileMenu.addItem(withTitle: "Save Snapshot to Desktop",
                                    action: #selector(BrowserWindowController.saveSnapshot(_:)), keyEquivalent: "s")
        snap.keyEquivalentModifierMask = [.command, .shift]
        let fullPageSnap = fileMenu.addItem(withTitle: "Save Full Page Snapshot to Desktop",
                                            action: #selector(BrowserWindowController.saveFullPageSnapshot(_:)),
                                            keyEquivalent: "s")
        fullPageSnap.keyEquivalentModifierMask = [.command, .option, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = fileMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let copyURL = editMenu.addItem(withTitle: "Copy Current URL",
                                       action: #selector(BrowserWindowController.copyPageURL(_:)), keyEquivalent: "c")
        copyURL.keyEquivalentModifierMask = [.command, .shift]
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Reload Page",
                         action: #selector(BrowserWindowController.reloadPage(_:)), keyEquivalent: "r")
        let hardReload = viewMenu.addItem(withTitle: "Reload Ignoring Cache",
                                          action: #selector(BrowserWindowController.hardReloadPage(_:)), keyEquivalent: "r")
        hardReload.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Zoom In",
                         action: #selector(BrowserWindowController.zoomInPage(_:)), keyEquivalent: "=")
        viewMenu.addItem(withTitle: "Zoom Out",
                         action: #selector(BrowserWindowController.zoomOutPage(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size",
                         action: #selector(BrowserWindowController.resetZoom(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen",
                                          action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = viewMenu

        let historyMenu = NSMenu(title: "History")
        historyMenu.addItem(withTitle: "Back",
                            action: #selector(BrowserWindowController.goBackAction(_:)), keyEquivalent: "[")
        historyMenu.addItem(withTitle: "Forward",
                            action: #selector(BrowserWindowController.goForwardAction(_:)), keyEquivalent: "]")
        main.addItem(withTitle: "History", action: nil, keyEquivalent: "").submenu = historyMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Pin on Top",
                           action: #selector(BrowserWindowController.togglePin(_:)), keyEquivalent: "p")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Chromeless Help",
                         action: #selector(BrowserWindowController.showHelpPage(_:)), keyEquivalent: "?")
        main.addItem(withTitle: "Help", action: nil, keyEquivalent: "").submenu = helpMenu
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
    }
}

// MARK: - Boot

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
