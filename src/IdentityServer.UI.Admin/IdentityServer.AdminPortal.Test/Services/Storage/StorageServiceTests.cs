// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json;
using Microsoft.JSInterop;
using NSubstitute;
using IdentityServer.AdminPortal.Web.Services.Storage;

namespace IdentityServer.AdminPortal.Web.Tests.Services.Storage;

[TestFixture]
public class SessionStorageServiceTests
{
    private IJSRuntime _jsRuntime;
    private SessionStorageService _sessionStorageService;

    [SetUp]
    public void SetUp()
    {
        _jsRuntime = Substitute.For<IJSRuntime>();
        _sessionStorageService = new SessionStorageService(_jsRuntime);
    }

    [Test]
    public async Task SetItem_WithValidKeyAndData_CallsJSRuntimeWithCorrectParameters()
    {
        // Arrange
        var key = "test-key";
        var data = new { Name = "Test", Value = 123 };
        var expectedJson = JsonSerializer.Serialize(data);

        // Act
        await _sessionStorageService.SetItem(key, data);

        // Assert
        await _jsRuntime.Received(1).InvokeVoidAsync("sessionStorage.setItem",
            Arg.Is<object[]>(args => args.Length == 2
                && args[0].ToString() == key
                && args[1].ToString() == expectedJson));
    }

    [Test]
    public async Task GetItem_WithValidKeyAndExistingData_ReturnsDeserializedObject()
    {
        // Arrange
        var key = "test-key";
        var originalData = new TestObject { Name = "Test", Value = 123 };
        var jsonData = JsonSerializer.Serialize(originalData);
        _jsRuntime.InvokeAsync<string>("sessionStorage.getItem", Arg.Any<object[]>()).Returns(jsonData);

        // Act
        var result = await _sessionStorageService.GetItem<TestObject>(key);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Name, Is.EqualTo(originalData.Name));
            Assert.That(result.Value, Is.EqualTo(originalData.Value));
            await _jsRuntime.Received(1).InvokeAsync<string>("sessionStorage.getItem",
                Arg.Is<object[]>(args => args.Length == 1 && args[0].ToString() == key));
        }
    }

    [Test]
    public async Task GetItem_WithValidKeyAndNonExistentData_ReturnsDefault()
    {
        // Arrange
        var key = "non-existent-key";
        _jsRuntime.InvokeAsync<string>("sessionStorage.getItem", Arg.Any<object[]>()).Returns((string)null);

        // Act
        var result = await _sessionStorageService.GetItem<string>(key);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public async Task GetItem_WithValidKeyAndEmptyStringData_ReturnsDefault()
    {
        // Arrange
        var key = "empty-key";
        _jsRuntime.InvokeAsync<string>("sessionStorage.getItem", Arg.Any<object[]>()).Returns("");

        // Act
        var result = await _sessionStorageService.GetItem<string>(key);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public async Task GetItem_WithValidJsonString_ReturnsCorrectlyDeserializedString()
    {
        // Arrange
        var key = "string-key";
        var originalString = "test string";
        var jsonData = JsonSerializer.Serialize(originalString);
        _jsRuntime.InvokeAsync<string>("sessionStorage.getItem", Arg.Any<object[]>()).Returns(jsonData);

        // Act
        var result = await _sessionStorageService.GetItem<string>(key);

        // Assert
        Assert.That(result, Is.EqualTo(originalString));
    }

    [Test]
    public async Task RemoveItem_WithValidKey_CallsJSRuntimeWithCorrectParameters()
    {
        // Arrange
        var key = "test-key";

        // Act
        await _sessionStorageService.RemoveItem(key);

        // Assert
        await _jsRuntime.Received(1).InvokeVoidAsync("sessionStorage.removeItem",
                Arg.Is<object[]>(args => args.Length == 1 && args[0].ToString() == key));
    }

    internal class TestObject
    {
        public string Name { get; set; }
        public int Value { get; set; }
    }
}
