# DotNative.WebView

Native in-app browser surfaces for DotNative on Android, iOS and macOS.

```csharp
builder.Services.AddWebView();
var browser = services.GetRequiredService<IWebView>();

await browser.OpenAsync(new Uri("https://example.com"), new WebViewOptions
{
    JavaScriptEnabled = false
});
await browser.GoBackAsync();
await browser.CloseAsync();
```

The plugin creates a native browser window/sheet with back, forward, reload and
close controls. It supports HTTP and HTTPS URLs, request headers, an optional
user agent, JavaScript evaluation, and current URL lookup. JavaScript is disabled
by default. Android blocks file/content access and mixed content.

## Platform coverage

| Platform | Status |
| --- | --- |
| Android | Native `android.webkit.WebView` window |
| iOS | Native `WKWebView` full-screen sheet |
| macOS | Native `WKWebView` window |
| Windows | Not implemented |
| Linux | Not implemented |

This first package is a native top-level surface. It cannot be embedded in a
DotNative layout, clipped by a scroll view, or positioned as an inline widget.
DotNative's renderer does not yet expose a native-view plugin contract. Android,
iOS and macOS require the DotNative native-plugin build path; Windows/Linux apps
fail clearly because this package has no implementation for those platforms.

URL navigation and JavaScript execute in the platform WebView. Treat page
content and JavaScript as untrusted. The package does not grant file URL access,
intercept navigation, or provide a native-to-web message bridge.

## Upstream

This is an independent DotNative implementation. It does not include or copy
Flutter/Dart source. The API is informed by the open-source
[webview_flutter](https://pub.dev/packages/webview_flutter) package (BSD-3-Clause)
and uses platform system WebView engines. Flutter's source and license remain at
[flutter/packages](https://github.com/flutter/packages/tree/main/packages/webview_flutter).

## Build

The project targets .NET 9 and packages as `DotNative.WebView`. For a local
checkout beside `dotNative`, it references the framework source. A standalone
checkout uses the published `DotNative` NuGet package. Native source is compiled
and linked by DotNative's plugin build pipeline.
