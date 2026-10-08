using System;
using Microsoft.Extensions.DependencyInjection;

namespace DotNative.WebView;

public static class WebViewServiceProviderExtensions
{
#if NET10_0_OR_GREATER
    extension(IServiceProvider services)
    {
        /// <summary>Resolves the registered plugin using the provider's DI lifetime.</summary>
        public IWebView WebView => services.GetRequiredService<IWebView>();
    }
#else
    /// <summary>Resolves the registered plugin using the provider's DI lifetime.</summary>
    public static IWebView WebView(this IServiceProvider services) =>
        services.GetRequiredService<IWebView>();
#endif
}
