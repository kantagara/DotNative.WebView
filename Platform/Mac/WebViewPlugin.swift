import AppKit
import Foundation
import WebKit

@MainActor private final class BrowserWindow: NSWindowController, WKNavigationDelegate {
  let browser: WKWebView
  private let titleLabel = NSTextField(labelWithString: "")
  private var actionTargets: [ActionTarget] = []

  init(url: URL, arguments: [String: PluginValue]) {
    let configuration = WKWebViewConfiguration()
    if case .bool(let enabled)? = arguments["javaScriptEnabled"] {
      configuration.defaultWebpagePreferences.allowsContentJavaScript = enabled
    }
    browser = WKWebView(frame: .zero, configuration: configuration)
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720))
    let toolbar = NSStackView()
    toolbar.orientation = .horizontal
    toolbar.spacing = 10
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.lineBreakMode = .byTruncatingMiddle
    let back = button("Back") { [weak self] in if self?.browser.canGoBack == true { self?.browser.goBack() } }
    let forward = button("Forward") { [weak self] in if self?.browser.canGoForward == true { self?.browser.goForward() } }
    let reload = button("Reload") { [weak self] in self?.browser.reload() }
    let close = button("Close") { [weak self] in self?.close() }
    [back, forward, reload, titleLabel, close].forEach(toolbar.addArrangedSubview)
    browser.translatesAutoresizingMaskIntoConstraints = false
    browser.navigationDelegate = self
    content.addSubview(toolbar)
    content.addSubview(browser)
    NSLayoutConstraint.activate([
      toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
      toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
      toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
      toolbar.heightAnchor.constraint(equalToConstant: 32),
      browser.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
      browser.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      browser.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      browser.bottomAnchor.constraint(equalTo: content.bottomAnchor),
    ])
    let window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = url.host ?? "WebView"
    window.contentView = content
    super.init(window: window)
    if case .string(let agent)? = arguments["userAgent"] { browser.customUserAgent = agent }
    var request = URLRequest(url: url)
    if case .map(let headers)? = arguments["headers"] {
      for (name, value) in headers { if case .string(let text) = value { request.setValue(text, forHTTPHeaderField: name) } }
    }
    browser.load(request)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  private func button(_ title: String, action: @escaping () -> Void) -> NSButton {
    let target = ActionTarget(action)
    actionTargets.append(target)
    let result = NSButton(title: title, target: target, action: #selector(ActionTarget.runAction(_:)))
    result.bezelStyle = .rounded
    return result
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    titleLabel.stringValue = webView.title ?? webView.url?.host ?? ""
    window?.title = titleLabel.stringValue
  }
}

@MainActor private final class ActionTarget: NSObject {
  private let action: () -> Void
  init(_ action: @escaping () -> Void) { self.action = action }
  @objc func runAction(_ sender: Any?) { action() }
}

@MainActor final class WebViewPlugin {
  private static var instance: WebViewPlugin?
  private var browser: BrowserWindow?
  static func register() { if instance == nil { instance = WebViewPlugin() } }

  private init() {
    let channel = NativeChannels.channel(WebViewChannel)
    channel.onReset = { [weak self] in self?.close() }
    channel.handle("open") { [weak self] args, reply in self?.open(args, reply) ?? reply.failure("unavailable", "WebView plugin is unavailable") }
    channel.handle("goBack") { [weak self] _, reply in reply.success(.bool(self?.moveBack() ?? false)) }
    channel.handle("goForward") { [weak self] _, reply in reply.success(.bool(self?.moveForward() ?? false)) }
    channel.handle("reload") { [weak self] _, reply in self?.browser?.browser.reload(); reply.success() }
    channel.handle("stop") { [weak self] _, reply in self?.browser?.browser.stopLoading(); reply.success() }
    channel.handle("getCurrentUrl") { [weak self] _, reply in
      if let url = self?.browser?.browser.url?.absoluteString { reply.success(.string(url)) }
      else { reply.success() }
    }
    channel.handle("evaluateJavaScript") { [weak self] args, reply in self?.evaluate(args, reply) ?? reply.failure("unavailable", "WebView plugin is unavailable") }
    channel.handle("close") { [weak self] _, reply in self?.close(); reply.success() }
  }

  private func open(_ args: PluginValue, _ reply: PluginReply) {
    guard let text = args.fields["url"]?.string, let url = URL(string: text),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil
    else { reply.failure("invalid_url", "An absolute HTTP or HTTPS URL is required"); return }
    close()
    let view = BrowserWindow(url: url, arguments: args.fields)
    browser = view
    view.showWindow(nil)
    reply.success()
  }
  private func close() { browser?.browser.stopLoading(); browser?.close(); browser = nil }
  private func moveBack() -> Bool { guard let web = browser?.browser, web.canGoBack else { return false }; web.goBack(); return true }
  private func moveForward() -> Bool { guard let web = browser?.browser, web.canGoForward else { return false }; web.goForward(); return true }
  private func evaluate(_ args: PluginValue, _ reply: PluginReply) {
    guard let script = args.fields["script"]?.string, let web = browser?.browser else {
      reply.failure("unavailable", "Open a WebView before evaluating JavaScript"); return
    }
    web.evaluateJavaScript(script) { value, error in
      if let error { reply.failure("javascript_failed", error.localizedDescription); return }
      switch value {
      case let text as String: reply.success(.string(text))
      case let number as NSNumber: reply.success(.string(number.stringValue))
      case nil: reply.success()
      default: reply.success(.string(String(describing: value!)))
      }
    }
  }
}
