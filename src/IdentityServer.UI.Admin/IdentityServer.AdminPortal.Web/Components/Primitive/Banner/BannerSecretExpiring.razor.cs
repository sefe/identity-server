// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.Options;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.AdminPortal.Web.Components.Primitive.Banner;

public partial class BannerSecretExpiring : BannerSecretBase
{
    [Inject]
    public IOptions<SecretExpirationConfig> SecretExpirationOptions { get; set; } = null!;

    protected override int GetFilteredSecretsCount()
    {
        return Secrets.Count(s => s.Expiration.IsExpiringSoon(SecretExpirationOptions.Value.DaysBeforeExpirationNotification));
    }

    protected override MarkupString GetBannerMessage(int secretsCount)
    {
        return (MarkupString)$"<strong>Secrets Expiring Soon:</strong> {secretsCount} {(secretsCount > 1 ? "secrets" : "secret")} will expire in less than {SecretExpirationOptions.Value.DaysBeforeExpirationNotification} days.";
    }
}