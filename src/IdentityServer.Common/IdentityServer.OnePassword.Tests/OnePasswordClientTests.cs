// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Net;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Tests.Common;

namespace IdentityServer.OnePassword.Tests;

[TestFixture]
public class OnePasswordClientTests
{
    private OnePasswordConfig _config;

    [SetUp]
    public void SetUp()
    {
        _config = new OnePasswordConfig
        {
            BaseUrl = "https://api.1password.com",
            VaultId = "vault",
            AccessToken = "test-token",
            Secrets = new Dictionary<string, string>()
        };
    }

    [Test]
    public async Task GetSecretValueAsync_OnCredentialCategory_ReturnsCredentialFieldValue()
    {
        // Arrange
        var item = new OnePasswordItem
        {
            Category = OnePasswordItem.CredentialCategory
        };
        item.Fields.Add(new OnePasswordField { Id = OnePasswordField.CredentialFieldId, Value = "cred-value" });
        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, item);
        var httpClient = new HttpClient(handler);
        var client = new OnePasswordClient(httpClient, _config);

        // Act
        var result = await client.GetSecretValueAsync("item");

        // Assert
        Assert.That(result, Is.EqualTo("cred-value"));
    }

    [Test]
    public async Task GetSecretValueAsync_OnLoginCategory_ReturnsPasswordFieldValue()
    {
        // Arrange
        var item = new OnePasswordItem
        {
            Category = OnePasswordItem.LoginCategory
        };
        item.Fields.Add(new OnePasswordField { Id = OnePasswordField.PasswordFieldId, Value = "pwd-value" });
        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, item);
        var httpClient = new HttpClient(handler);
        var client = new OnePasswordClient(httpClient, _config);

        // Act
        var result = await client.GetSecretValueAsync("item");

        // Assert
        Assert.That(result, Is.EqualTo("pwd-value"));
    }

    [Test]
    public void GetSecretValueAsync_OnUnknownCategory_ThrowsException()
    {
        // Arrange
        var item = new OnePasswordItem
        {
            Category = "other"
        };
        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, item);
        var httpClient = new HttpClient(handler);
        var client = new OnePasswordClient(httpClient, _config);

        // Act & Assert
        var exception = Assert.ThrowsAsync<IdentityServerException>(() => client.GetSecretValueAsync("item"));
        Assert.That(exception.Message, Does.Contain($"'other' category is not supported. Vault 'vault', item 'item'."));
    }

    [Test]
    public void GetSecretValueAsync_OnEmptyResponse_ThrowsException()
    {
        // Arrange
        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, "{}");
        var httpClient = new HttpClient(handler);
        var client = new OnePasswordClient(httpClient, _config);

        // Act & Assert
        var exception = Assert.ThrowsAsync<IdentityServerException>(() => client.GetSecretValueAsync("item"));
        Assert.That(exception.Message, Does.Contain($"'' category is not supported. Vault 'vault', item 'item'."));
    }

    [Test]
    public void GetSecretValueAsync_OnUnreadableResponse_ThrowsException()
    {
        // Arrange
        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, false);
        var httpClient = new HttpClient(handler);
        var client = new OnePasswordClient(httpClient, _config);

        // Act & Assert
        var exception = Assert.ThrowsAsync<IdentityServerException>(() => client.GetSecretValueAsync("item"));
        Assert.That(exception.Message, Does.Contain($"Failed to deserialize 1Password response for item 'item'"));
    }

    [TestCase("<html><head>text</head><body>test</body></html>")]
    [TestCase("")]
    [TestCase("{\"field1\":\"value\"")]
    public void GetSecretValueAsync_OnDeserializationError_ThrowsException(string response)
    {
        // Arrange
        var handler = new MockHttpMessageHandler(HttpStatusCode.OK, response);
        var httpClient = new HttpClient(handler);
        var client = new OnePasswordClient(httpClient, _config);

        // Act & Assert
        var exception = Assert.ThrowsAsync<IdentityServerException>(() => client.GetSecretValueAsync("item"));
        Assert.That(exception.Message, Does.Contain($"Failed to deserialize 1Password response for item 'item' in vault 'vault'. Response: {response}"));
    }

    [Test]
    public void GetSecretValueAsync_OnHttpError_ThrowsException()
    {
        // Arrange
        var handler = new MockHttpMessageHandler(HttpStatusCode.BadRequest, "error");
        var httpClient = new HttpClient(handler);
        var client = new OnePasswordClient(httpClient, _config);

        // Act & Assert
        var exception = Assert.ThrowsAsync<IdentityServerException>(async () =>
            await client.GetSecretValueAsync("item"));
        Assert.That(exception.Message, Does.Contain("Error fetching item 'item' in vault 'vault' from 1Password. Status code: BadRequest. Response: error"));
    }
}
