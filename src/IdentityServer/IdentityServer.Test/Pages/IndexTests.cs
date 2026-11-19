// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Licensing;
using Index = IdentityServer.Pages.Index;

namespace IdentityServer.Test.Pages;

[TestFixture]
public class IndexTests
{
    [Test]
    public void Constructor_WhenLicenseMissing_ShouldNotExposeLicense()
    {
        Assert.That(new Index().License, Is.Null);
    }

    [Test]
    public void Constructor_WhenLicenseUnconfigured_ShouldNotExposeLicense()
    {
        var page = new Index(new LicenseInformation());

        Assert.That(page.License, Is.Null);
    }

    [Test]
    public void Constructor_WhenLicenseConfigured_ShouldExposeLicense()
    {
        var license = new LicenseInformation
        {
            IsConfigured = true,
            Expiration = DateTimeOffset.UtcNow.AddYears(1)
        };

        var page = new Index(license);

        Assert.That(page.License, Is.SameAs(license));
    }
}
