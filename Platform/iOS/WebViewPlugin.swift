import Foundation
import WebKit
import UIKit

@MainActor private final class WebViewController: UIViewController, WKNavigationDelegate {
  let browser: WKWebView
  var onClose: (() -> Void)?
  private let titleLabel = UILabel()

  init(url: URL, arguments: [String: PluginValue]) {
    let configuration = WKWebViewConfiguration()
    if let enabled = arguments["javaScriptEnabled"], case .bool(let value) = enabled {
      configuration.defaultWebpagePreferences.allowsContentJavaScript = value
    }
    browser = WKWebView(frame: .zero, configuration: configuration)
    super.init(nibName: nil, bundle: nil)
    browser.navigationDelegate = self
    titleLabel.font = .systemFont(ofSize: 12)
    titleLabel.lineBreakMode = .byTruncatingMiddle
    titleLabel.textAlignment = .center
    if case .string(let agent)? = arguments["userAgent"], !agent.isEmpty {
      browser.customUserAgent = agent
    }
    var request = URLRequest(url: url)
    if case .map(let headers)? = arguments["headers"] {
      for (name, value) in headers {
        if case .string(let text) = value { request.setValue(text, forHTTPHeaderField: name) }
      }
    }
    browser.load(request)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let toolbar = UIStackView()
    toolbar.axis = .horizontal
    toolbar.spacing = 10
    toolbar.alignment = .center
    let back = button("‹") { [weak self] in if self?.browser.canGoBack == true { self?.browser.goBack() } }
    let forward = button("›") { [weak self] in if self?.browser.canGoForward == true { self?.browser.goForward() } }
    let reload = button("↻") { [weak self] in self?.browser.reload() }
    let close = button("Done") { [weak self] in self?.onClose?() }
    titleLabel.text = browser.url?.host
    toolbar.addArrangedSubview(back)
    toolbar.addArrangedSubview(forward)
    toolbar.addArrangedSubview(reload)
    toolbar.addArrangedSubview(titleLabel)
    toolbar.addArrangedSubview(close)
    titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    browser.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(toolbar)
    view.addSubview(browser)
    NSLayoutConstraint.activate([
      toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
      toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      toolbar.heightAnchor.constraint(equalToConstant: 40),
      browser.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 4),
      browser.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      browser.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      browser.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
    let result = UIButton(type: .system)
    result.setTitle(title, for: .normal)
    result.addAction(UIAction { _ in action() }, for: .touchUpInside)
    return result
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    titleLabel.text = webView.title ?? webView.url?.host
  }
}

@MainActor final class WebViewPlugin {
  private static var instance: WebViewPlugin?
  private var controller: WebViewController?
  private var presentation: UIViewController?

  static func register() { if instance == nil { instance = WebViewPlugin() } }

  private init() {
    let channel = NativeChannels.channel(WebViewChannel)
    channel.onReset = { [weak self] in self?.close() }
    channel.handle("open") { [weak self] arguments, reply in self?.open(arguments, reply) ?? reply.failure("unavailable", "WebView plugin is unavailable") }
    channel.handle("goBack") { [weak self] _, reply in reply.success(.bool(self?.moveBack() ?? false)) }
    channel.handle("goForward") { [weak self] _, reply in reply.success(.bool(self?.moveForward() ?? false)) }
    channel.handle("reload") { [weak self] _, reply in self?.controller?.browser.reload(); reply.success() }
    channel.handle("stop") { [weak self] _, reply in self?.controller?.browser.stopLoading(); reply.success() }
    channel.handle("getCurrentUrl") { [weak self] _, reply in
      if let url = self?.controller?.browser.url?.absoluteString { reply.success(.string(url)) }
      else { reply.success() }
    }
    channel.handle("evaluateJavaScript") { [weak self] arguments, reply in self?.evaluate(arguments, reply) ?? reply.failure("unavailable", "WebView plugin is unavailable") }
    channel.handle("close") { [weak self] _, reply in self?.close(); reply.success() }
  }

  private func open(_ arguments: PluginValue, _ reply: PluginReply) {
    let fields = arguments.fields
    guard let text = fields["url"]?.string, let url = URL(string: text),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil
    else { reply.failure("invalid_url", "An absolute HTTP or HTTPS URL is required"); return }
    guard let presenter = NativeChannels.presenter else {
      reply.failure("unavailable", "No active iOS view controller is available"); return
    }
    close()
    let browser = WebViewController(url: url, arguments: fields)
    let sheet = UINavigationController(rootViewController: browser)
    sheet.modalPresentationStyle = .fullScreen
    browser.onClose = { [weak self] in self?.close() }
    controller = browser
    presentation = sheet
    presenter.present(sheet, animated: true)
    reply.success()
  }

  private func close() {
    let current = presentation
    presentation = nil
    controller?.browser.stopLoading()
    controller = nil
    current?.dismiss(animated: true)
  }

  private func moveBack() -> Bool {
    guard let browser = controller?.browser, browser.canGoBack else { return false }
    browser.goBack(); return true
  }
  private func moveForward() -> Bool {
    guard let browser = controller?.browser, browser.canGoForward else { return false }
    browser.goForward(); return true
  }
  private func evaluate(_ arguments: PluginValue, _ reply: PluginReply) {
    guard let script = arguments.fields["script"]?.string, let browser = controller?.browser else {
      reply.failure("unavailable", "Open a WebView before evaluating JavaScript"); return
    }
    browser.evaluateJavaScript(script) { value, error in
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
