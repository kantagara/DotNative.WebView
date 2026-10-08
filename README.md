# DotNative.WebView

Native in-app browser surfaces for DotNative on Android, iOS and macOS.

```csharp
builder.Services.AddWebView();
var browser = services.WebView;

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

For Android, add `android.permission.INTERNET` to the app manifest. iOS/macOS
App Transport Security and Android cleartext-traffic policy still apply; use
HTTPS unless the application deliberately configures local HTTP access.

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

## Source origin

This independently authored DotNative implementation is MIT licensed and uses
platform system WebView engines. See [source origin](ORIGIN.md).

## Build

The project targets .NET 9 and .NET 10 and packages as `DotNative.WebView`. For a local
checkout beside `dotNative`, it references the framework source. A standalone
checkout uses the published `DotNative` NuGet package. Native source is compiled
and linked by DotNative's plugin build pipeline.

## Service access

Import `DotNative.WebView` to access the plugin through `IServiceProvider`:

```csharp
using DotNative.WebView;

var plugin = services.WebView;
```

The getter calls `GetRequiredService<IWebView>()` on every access, preserving
DI lifetimes and the usual missing-registration error. Register the plugin with
`AddWebView(...)` before building the provider.

A `net10.0` application uses the property syntax with C# 14 or later. A
`net9.0` application uses only the method equivalent:

```csharp
var plugin = services.WebView();
```

The package contains separate `net9.0` and `net10.0` assemblies. NuGet selects
the assembly matching the application target framework. `NET10_0_OR_GREATER`
selects the property; the `#else` branch selects the method.

Build and pack both targets with .NET 10 SDK. A source build using .NET 9 SDK
builds only `net9.0`; it does not produce the .NET 10 assembly.
