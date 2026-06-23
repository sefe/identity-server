// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Configs;

/// <summary>
/// Controls custom token logging behavior. Used by <see cref="CustomLoggingTokenService"/>.
/// </summary>
public class CustomTokenLoggingSettings
{
    /// <summary>
    /// Enable or disable custom token logging.
    /// </summary>
    public bool EnableCustomTokenLogging { get; set; }

    /// <summary>
    /// How many characters of a reference token to log.
    /// Is only effective if <see cref="EnableCustomTokenLogging"/> is true.
    /// The value is respected only if actual token length is at least twice as long as the value,
    /// otherwise only half of the token is logged.
    /// </summary>
    public int ReferenceTokenDefaultVisibleLength { get; set; }

    /// <summary>
    /// How many parts of a JWT token to log.
    /// Signature can never be logged for security reasons.
    /// </summary>
    public JwtTokenVisibleParts JwtTokenVisibleParts { get; set; }
}
