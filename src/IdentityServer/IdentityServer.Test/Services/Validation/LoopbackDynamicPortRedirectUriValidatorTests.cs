// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Configuration;
using Duende.IdentityServer.Models;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Services.Validation;

namespace IdentityServer.Test.Services.Validation;

[TestFixture]
public class LoopbackDynamicPortRedirectUriValidatorTests
{
    private LoopbackDynamicPortRedirectUriValidator _validator;
    private ILogger<LoopbackDynamicPortRedirectUriValidator> _logger;

    [SetUp]
    public void SetUp()
    {
        _logger = Substitute.For<ILogger<LoopbackDynamicPortRedirectUriValidator>>();
        _validator = new LoopbackDynamicPortRedirectUriValidator(_logger, new IdentityServerOptions());
    }

    // localhost
    [TestCase("http://localhost/path", "http://localhost/path", true)]
    [TestCase("http://LOCALhost/path", "http://LOCALhost/path", true)]
    [TestCase("http://LOCALhost/path", "http://localhost/path", false)]
    [TestCase("HTTP://localhost/path", "HTTP://localhost/path", true)]
    [TestCase("HTTP://localhost/path", "http://localhost/path", false)]
    [TestCase("http://localhost/PATH?tenant=abc&env=dv", "http://localhost/PATH?tenant=abc&env=dv", true)]
    [TestCase("http://localhost/path", "http://localhost:5000/path", true)]
    [TestCase("http://localhost", "http://localhost", true)]
    [TestCase("http://localhost", "http://localhost:5000", true)]
    [TestCase("http://127.0.0.1/path", "http://127.0.0.1/path", true)]
    [TestCase("http://127.0.0.1/path", "http://127.0.0.1:5000/path", true)]
    [TestCase("http://127.0.0.1", "http://127.0.0.1", true)]
    [TestCase("http://127.0.0.1", "http://127.0.0.1:5000", true)]
    [TestCase("http://localhost:1234", "http://localhost:1234/path", false)]
    [TestCase("http://localhost:1234/path", "http://localhost:1234", false)]
    [TestCase("http://localhost:1234/path", "http://localhost:5678/path", false)]
    [TestCase("http://localhost/path", "https://localhost/path", false)]
    [TestCase("http://localhost/path", "http://127.0.0.1/path", false)]
    [TestCase("http://127.0.0.1/path", "http://localhost/path", false)]
    [TestCase("http://localhost/path", "http://localhost/PATH", false)]
    [TestCase("http://localhost/path", "http://LOCALhost/path", false)]
    [TestCase("http://localhost/path", "HTTP://localhost/path", false)]
    [TestCase("http://localhost/path/path2", "http://localhost/path/PATH2", false)]
    [TestCase("http://localhost/PATH?tenant=abc&ENV=dv", "http://localhost/PATH?tenant=abc&env=dv", false)]
    [TestCase("http://localhost/PATH?tenant=abc&ENV=DV", "http://localhost/PATH?tenant=abc&ENV=dv", false)]
    // non-localhost
    [TestCase("http://myApp/path", "http://myApp/path", true)]
    [TestCase("http://myApp/PATH/path1", "http://myApp/PATH/path1", true)]
    [TestCase("HTTP://myApp/path?tenant=abc", "HTTP://myApp/path?tenant=abc", true)]
    [TestCase("http://myApp:1234/path", "http://myApp:1234/path", true)]
    [TestCase("http://myApp:1234/path", "http://myApp:5678/path", false)]
    [TestCase("http://myApp:1234/path", "http://myApp/path", false)]
    [TestCase("http://myApp/path", "https://myApp/path", false)]
    [TestCase("http://myApp/path", "HTTP://myApp/path", false)]
    [TestCase("http://myApp/path", "http://MYAPP/path", false)]
    [TestCase("http://myApp/path", "http://myApp/PATH", false)]
    [TestCase("HTTP://myApp/path?TENANT=abc", "HTTP://myApp/path?tenant=abc", false)]
    [TestCase("HTTP://myApp/path?TENANT=ABC", "HTTP://myApp/path?TENANT=abc", false)]
    // malformed
    [TestCase("://myApp/path", "http://myApp/path", false)]
    [TestCase("/myApp/path", "http://myApp/path", false)]
    [TestCase("myApp/path", "http://myApp/path", false)]
    [TestCase("myApp", "http://myApp/path", false)]
    [TestCase("http://myApp/path", "://myApp/path", false)]
    [TestCase("http://myApp/path", "/myApp/path", false)]
    [TestCase("http://myApp/path", "myApp/path", false)]
    [TestCase("http://myApp/path", "myApp", false)]
    public async Task IsRedirectUriValidAsync_ProduceExpectedResult(string configuredUri, string actualUri, bool expectedResult)
    {
        // Arrange
        var client = new Client
        {
            RedirectUris = new List<string> { configuredUri }
        };

        // Act
        var result = await _validator.IsRedirectUriValidAsync(actualUri, client);

        // Assert
        Assert.That(result, Is.EqualTo(expectedResult));
    }

    // localhost
    [TestCase("http://localhost/path", "http://localhost/path", true)]
    [TestCase("http://LOCALhost/path", "http://LOCALhost/path", true)]
    [TestCase("http://LOCALhost/path", "http://localhost/path", false)]
    [TestCase("HTTP://localhost/path", "HTTP://localhost/path", true)]
    [TestCase("HTTP://localhost/path", "http://localhost/path", false)]
    [TestCase("http://localhost/PATH?tenant=abc&env=dv", "http://localhost/PATH?tenant=abc&env=dv", true)]
    [TestCase("http://localhost/path", "http://localhost:5000/path", true)]
    [TestCase("http://localhost", "http://localhost", true)]
    [TestCase("http://localhost", "http://localhost:5000", true)]
    [TestCase("http://127.0.0.1/path", "http://127.0.0.1/path", true)]
    [TestCase("http://127.0.0.1/path", "http://127.0.0.1:5000/path", true)]
    [TestCase("http://127.0.0.1", "http://127.0.0.1", true)]
    [TestCase("http://127.0.0.1", "http://127.0.0.1:5000", true)]
    [TestCase("http://localhost:1234", "http://localhost:1234/path", false)]
    [TestCase("http://localhost:1234/path", "http://localhost:1234", false)]
    [TestCase("http://localhost:1234/path", "http://localhost:5678/path", false)]
    [TestCase("http://localhost/path", "https://localhost/path", false)]
    [TestCase("http://localhost/path", "http://127.0.0.1/path", false)]
    [TestCase("http://127.0.0.1/path", "http://localhost/path", false)]
    [TestCase("http://localhost/path", "http://localhost/PATH", false)]
    [TestCase("http://localhost/path", "http://LOCALhost/path", false)]
    [TestCase("http://localhost/path", "HTTP://localhost/path", false)]
    [TestCase("http://localhost/path/path2", "http://localhost/path/PATH2", false)]
    [TestCase("http://localhost/PATH?tenant=abc&ENV=dv", "http://localhost/PATH?tenant=abc&env=dv", false)]
    [TestCase("http://localhost/PATH?tenant=abc&ENV=DV", "http://localhost/PATH?tenant=abc&ENV=dv", false)]
    // non-localhost
    [TestCase("http://myApp/path", "http://myApp/path", true)]
    [TestCase("http://myApp/PATH/path1", "http://myApp/PATH/path1", true)]
    [TestCase("HTTP://myApp/path?tenant=abc", "HTTP://myApp/path?tenant=abc", true)]
    [TestCase("http://myApp:1234/path", "http://myApp:1234/path", true)]
    [TestCase("http://myApp:1234/path", "http://myApp:5678/path", false)]
    [TestCase("http://myApp:1234/path", "http://myApp/path", false)]
    [TestCase("http://myApp/path", "https://myApp/path", false)]
    [TestCase("http://myApp/path", "HTTP://myApp/path", false)]
    [TestCase("http://myApp/path", "http://MYAPP/path", false)]
    [TestCase("http://myApp/path", "http://myApp/PATH", false)]
    [TestCase("HTTP://myApp/path?TENANT=abc", "HTTP://myApp/path?tenant=abc", false)]
    [TestCase("HTTP://myApp/path?TENANT=ABC", "HTTP://myApp/path?TENANT=abc", false)]
    // malformed
    [TestCase("://myApp/path", "http://myApp/path", false)]
    [TestCase("/myApp/path", "http://myApp/path", false)]
    [TestCase("myApp/path", "http://myApp/path", false)]
    [TestCase("myApp", "http://myApp/path", false)]
    [TestCase("http://myApp/path", "://myApp/path", false)]
    [TestCase("http://myApp/path", "/myApp/path", false)]
    [TestCase("http://myApp/path", "myApp/path", false)]
    [TestCase("http://myApp/path", "myApp", false)]
    public async Task IsPostLogoutRedirectUriValidAsync_ProduceExpectedResult(string configuredUri, string actualUri, bool expectedResult)
    {
        // Arrange
        var client = new Client
        {
            PostLogoutRedirectUris = new List<string> { configuredUri }
        };

        // Act
        var result = await _validator.IsPostLogoutRedirectUriValidAsync(actualUri, client);

        // Assert
        Assert.That(result, Is.EqualTo(expectedResult));
    }
}
