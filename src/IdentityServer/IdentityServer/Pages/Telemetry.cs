// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Diagnostics.Metrics;

namespace IdentityServer.Pages;

/// <summary>
/// Telemetry helpers for the UI
/// </summary>
public static class Telemetry
{
    private static readonly string _serviceVersion = typeof(Telemetry).Assembly.GetName().Version!.ToString();

    /// <summary>
    /// Service name for telemetry.
    /// </summary>
    public static readonly string ServiceName = typeof(Telemetry).Assembly.GetName().Name!;

    /// <summary>
    /// Metrics configuration
    /// </summary>
    public static class Metrics
    {
        /// <summary>
        /// Name of Counters
        /// </summary>
        public static class Counters
        {
            public const string Consent = "tokenservice.consent";
            public const string GrantsRevoked = "tokenservice.grants_revoked";
            public const string UserLogin = "tokenservice.user_login";
            public const string UserLogout = "tokenservice.user_logout";
        }

        /// <summary>
        /// Name of tags
        /// </summary>
        public static class Tags
        {
            public const string Client = "client";
            public const string Error = "error";
            public const string Idp = "idp";
            public const string Remember = "remember";
            public const string Scope = "scope";
            public const string Consent = "consent";
        }

        /// <summary>
        /// Values of tags
        /// </summary>
        public static class TagValues
        {
            public const string Granted = "granted";
            public const string Denied = "denied";
        }

        /// <summary>
        /// Meter for the IdentityServer host project
        /// </summary>
        private static readonly Meter _meter = new(ServiceName, _serviceVersion);

        private static readonly Counter<long> _consentCounter = _meter.CreateCounter<long>(Counters.Consent);

        /// <summary>
        /// Helper method to increase <see cref="Counters.Consent"/> counter. The scopes
        /// are expanded and called one by one to not cause a combinatory explosion of scopes.
        /// </summary>
        /// <param name="clientId">Client id</param>
        /// <param name="scopes">Scope names. Each element is added on it's own to the counter</param>
        public static void TrackConsentGranted(string clientId, IEnumerable<string> scopes, bool remember)
        {
            ArgumentNullException.ThrowIfNull(scopes);

            foreach (var scope in scopes)
            {
                var tags = new[]{
                    new KeyValuePair<string, object?>(Tags.Client, clientId),
                    new KeyValuePair<string, object?>(Tags.Scope, scope),
                    new KeyValuePair<string, object?>(Tags.Remember, remember),
                    new KeyValuePair<string, object?>(Tags.Consent, TagValues.Granted),
                };

                _consentCounter.Add(1, tags);
            }
        }

        /// <summary>
        /// Helper method to increase <see cref="Counters.ConsentDenied"/> counter. The scopes
        /// are expanded and called one by one to not cause a combinatory explosion of scopes.
        /// </summary>
        /// <param name="clientId">Client id</param>
        /// <param name="scopes">Scope names. Each element is added on it's own to the counter</param>
        public static void TrackConsentDenied(string clientId, IEnumerable<string> scopes)
        {
            ArgumentNullException.ThrowIfNull(scopes);
            foreach (var scope in scopes)
            {
                _consentCounter.Add(1, new(Tags.Client, clientId), new(Tags.Scope, scope), new(Tags.Consent, TagValues.Denied));
            }
        }

        private static readonly Counter<long> _grantsRevokedCounter = _meter.CreateCounter<long>(Counters.GrantsRevoked);

        /// <summary>
        /// Helper method to increase the <see cref="Counters.GrantsRevoked"/> counter.
        /// </summary>
        /// <param name="clientId">Client id to revoke for, or null for all.</param>
        public static void TrackGrantsRevoked(string? clientId)
            => _grantsRevokedCounter.Add(1, tag: new(Tags.Client, clientId));

        private static readonly Counter<long> _userLoginCounter = _meter.CreateCounter<long>(Counters.UserLogin);

        /// <summary>
        /// Helper method to increase <see cref="Counters.UserLogin"/> counter.
        /// </summary>
        /// <param name="clientId">Client Id, if available</param>
        public static void TrackUserLogin(string? clientId, string idp)
            => _userLoginCounter.Add(1, new(Tags.Client, clientId), new(Tags.Idp, idp));

        /// <summary>
        /// Helper method to increase <see cref="Counters.UserLogin" counter on failure.
        /// </summary>
        /// <param name="clientId">Client Id, if available</param>
        /// <param name="error">Error message</param>
        public static void TrackUserLoginFailure(string? clientId, string idp, string error)
            => _userLoginCounter.Add(1, new(Tags.Client, clientId), new(Tags.Idp, idp), new(Tags.Error, error));

        private static readonly Counter<long> _userLogoutCounter = _meter.CreateCounter<long>(Counters.UserLogout);

        /// <summary>
        /// Helper method to increase the <see cref="Counters.UserLogout"/> counter.
        /// </summary>
        /// <param name="idp">Idp/authentication scheme for external authentication, or "local" for built in.</param>
        public static void TrackUserLogout(string? idp)
            => _userLogoutCounter.Add(1, tag: new(Tags.Idp, idp));
    }
}
