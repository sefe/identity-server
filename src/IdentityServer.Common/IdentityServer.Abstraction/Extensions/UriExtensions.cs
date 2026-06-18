namespace IdentityServer.Abstraction.Extensions;

public static class UriExtensions
{
    /// <summary>
    /// Determines whether the specified <see cref="Uri"/> represents a loopback address.
    /// </summary>
    /// <remarks>This method performs a case-insensitive comparison of host name against the value of "localhost" or "127.0.0.1".</remarks>
    /// <param name="actualUri">The <see cref="Uri"/> to evaluate. Must not be <see langword="null"/>.</param>
    /// <returns><see langword="true"/> if the <paramref name="actualUri"/> is a loopback address;
    /// otherwise, <see langword="false"/>.</returns>
    public static bool IsLoopbackUri(this Uri actualUri)
    {
        return string.Equals(actualUri.Host, "localhost", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(actualUri.Host, "127.0.0.1", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Determines whether the specified <see cref="Uri"/> supports dynamic port assignment.
    /// </summary>
    /// <param name="actualUri">The <see cref="Uri"/> instance to evaluate.</param>
    /// <returns><see langword="true"/> if the <paramref name="actualUri"/> uses the default port for its scheme; otherwise, <see
    /// langword="false"/>.</returns>
    /// <remarks>Only makes sense for loopback addresses.</remarks>
    public static bool IsDynamicPortAllowed(this Uri actualUri)
    {
        return actualUri.IsDefaultPort;
    }
}
