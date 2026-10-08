using DotNative.Plugins;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace DotNative.WebView;

public interface IWebView
{
    Task OpenAsync(Uri uri, WebViewOptions? options = null, CancellationToken cancellationToken = default);
    Task<bool> GoBackAsync(CancellationToken cancellationToken = default);
    Task<bool> GoForwardAsync(CancellationToken cancellationToken = default);
    Task ReloadAsync(CancellationToken cancellationToken = default);
    Task StopLoadingAsync(CancellationToken cancellationToken = default);
    Task CloseAsync(CancellationToken cancellationToken = default);
    Task<string?> GetCurrentUrlAsync(CancellationToken cancellationToken = default);
    Task<string?> EvaluateJavaScriptAsync(string script, CancellationToken cancellationToken = default);
}

public sealed record WebViewOptions
{
    public bool JavaScriptEnabled { get; init; }
    public string? UserAgent { get; init; }
    public IReadOnlyDictionary<string, string>? Headers { get; init; }
}

public static class WebViewServices
{
    public static IServiceCollection AddWebView(this IServiceCollection services)
    {
        services.TryAddSingleton<IWebView, ChannelWebView>();
        return services;
    }
}

internal sealed class ChannelWebView(IPlatformChannels channels) : IWebView
{
    private MethodChannel Channel => channels.Get(WebViewChannel.Id);

    public Task OpenAsync(Uri uri, WebViewOptions? options = null, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(uri);
        if (uri.Scheme is not ("http" or "https") || !uri.IsAbsoluteUri || string.IsNullOrEmpty(uri.Host))
            throw new ArgumentException("WebView accepts an absolute HTTP or HTTPS URL.", nameof(uri));
        options ??= new();
        var args = new Dictionary<string, object?>
        {
            ["url"] = uri.AbsoluteUri,
            ["javaScriptEnabled"] = options.JavaScriptEnabled,
            ["userAgent"] = options.UserAgent,
            ["headers"] = options.Headers is null ? null : new Dictionary<string, object?>(options.Headers.ToDictionary(p => p.Key, p => (object?)p.Value)),
        };
        return Channel.InvokeAsync("open", args, cancellationToken);
    }

    public async Task<bool> GoBackAsync(CancellationToken cancellationToken = default) =>
        await Bool("goBack", cancellationToken).ConfigureAwait(false);
    public async Task<bool> GoForwardAsync(CancellationToken cancellationToken = default) =>
        await Bool("goForward", cancellationToken).ConfigureAwait(false);
    public Task ReloadAsync(CancellationToken cancellationToken = default) => Call("reload", cancellationToken);
    public Task StopLoadingAsync(CancellationToken cancellationToken = default) => Call("stop", cancellationToken);
    public Task CloseAsync(CancellationToken cancellationToken = default) => Call("close", cancellationToken);
    public async Task<string?> GetCurrentUrlAsync(CancellationToken cancellationToken = default) =>
        await String("getCurrentUrl", cancellationToken).ConfigureAwait(false);
    public async Task<string?> EvaluateJavaScriptAsync(string script, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(script);
        return await String("evaluateJavaScript", cancellationToken, new Dictionary<string, object?> { ["script"] = script }).ConfigureAwait(false);
    }

    private Task Call(string method, CancellationToken token) => Channel.InvokeAsync(method, cancellationToken: token);
    private async Task<bool> Bool(string method, CancellationToken token)
    {
        var result = await Channel.InvokeAsync(method, cancellationToken: token).ConfigureAwait(false);
        return result is bool value ? value : throw new InvalidDataException($"Invalid {method} response.");
    }
    private async Task<string?> String(string method, CancellationToken token, object? args = null)
    {
        var result = await Channel.InvokeAsync(method, args, token).ConfigureAwait(false);
        return result is null or string ? (string?)result : throw new InvalidDataException($"Invalid {method} response.");
    }
}
