// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Validation;

namespace IdentityServer.Services;

/// <summary>
/// Selects an ITokenValidator implementation for the provided token.
/// </summary>
public interface ITokenValidatorSelector
{
    ITokenValidator SelectValidator(string token);
}
