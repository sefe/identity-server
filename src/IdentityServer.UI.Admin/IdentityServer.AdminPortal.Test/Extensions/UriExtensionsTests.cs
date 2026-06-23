// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.AdminPortal.Test.Extensions;

[TestFixture]
public class UriExtensionsTests
{
    [TestCase("http://localhost", true)]
    [TestCase("https://localhost", true)]
    [TestCase("http://127.0.0.1", true)]
    [TestCase("https://127.0.0.1", true)]
    [TestCase("http://example.com", false)]
    [TestCase("https://192.168.1.1", false)]
    [TestCase("aaa://test", false)]
    public void IsLoopbackUri_ReturnsExpectedResult(string uriString, bool expected)
    {
        // Arrange
        var uri = new Uri(uriString);

        // Act
        var result = uri.IsLoopbackUri();

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }

    [TestCase("http://localhost", true)]
    [TestCase("http://localhost:80", true)]
    [TestCase("http://localhost:8080", false)]
    [TestCase("https://localhost", true)]
    [TestCase("https://localhost:443", true)]
    [TestCase("https://localhost:4443", false)]
    public void IsDynamicPortAllowed_ReturnsExpectedResult(string uriString, bool expected)
    {
        // Arrange
        var uri = new Uri(uriString);

        // Act
        var result = uri.IsDynamicPortAllowed();

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }
}
