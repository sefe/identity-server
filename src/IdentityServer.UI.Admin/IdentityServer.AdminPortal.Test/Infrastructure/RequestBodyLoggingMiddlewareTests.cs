// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Http;
using System.Diagnostics.CodeAnalysis;
using IdentityServer.AdminPortal.Server.Infrastructure;
using static IdentityServer.Abstraction.Constants;
using System.Text;

namespace IdentityServer.AdminPortal.Test.Infrastructure;

[ExcludeFromCodeCoverage]
public class RequestBodyLoggingMiddlewareTests
{
    [TestCase("POST")]
    [TestCase("PUT")]
    [TestCase("DELETE")]
    [TestCase("PATCH")]
    public async Task Invoke_OnWriteOperations_ShouldAddRequestBodyToHttoContextItemsAndCallNext(string httpMethod)
    {
        // Arrange
        var requestBody = "hello";
        var httpContext = CreateHttpContext(httpMethod, requestBody);
        var wasCalled = false;
        RequestDelegate next = ctx =>
        {
            wasCalled = true;
            return Task.CompletedTask;
        };
        var middleware = CreateSut(next);

        // Act
        await middleware.Invoke(httpContext);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(httpContext.Items.ContainsKey(CustomContextFields.RequestBody), Is.True);
            Assert.That(httpContext.Items[CustomContextFields.RequestBody], Is.EqualTo(requestBody));
            Assert.That(httpContext.Request.Body.Position, Is.Zero);
            Assert.That(wasCalled, Is.True);
        }
    }

    [Test]
    public async Task Invoke_OnGetOperations_ShoulNotPopulateContextItemsAndCallNext()
    {
        // Arrange
        var httpContext = CreateHttpContext("GET", "body");
        var wasCalled = false;
        RequestDelegate next = ctx =>
        {
            wasCalled = true;
            return Task.CompletedTask;
        };
        var middleware = CreateSut(next);

        // Act
        await middleware.Invoke(httpContext);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(httpContext.Items.ContainsKey(CustomContextFields.RequestBody), Is.False);
            Assert.That(httpContext.Request.Body.Position, Is.Zero);
            Assert.That(wasCalled, Is.True);
        }
    }

    [Test]
    public async Task Invoke_OnError_ShoulNotPopulateContextItemsAndCallNext()
    {
        // Arrange
        var httpContext = new DefaultHttpContext();
        httpContext.Request.Method = "POST";
        var ms = new MemoryStream(Encoding.UTF8.GetBytes("test"));
        ms.Dispose();
        httpContext.Request.Body = ms; // disposed stream causes an exception when reading Body

        var wasCalled = false;
        RequestDelegate next = ctx =>
        {
            wasCalled = true;
            return Task.CompletedTask;
        };
        var middleware = CreateSut(next);

        // Act
        await middleware.Invoke(httpContext);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(httpContext.Items.ContainsKey(CustomContextFields.RequestBody), Is.False);
            Assert.That(httpContext.Request.Body.Position, Is.Zero);
            Assert.That(wasCalled, Is.True);
        }
    }

    private static DefaultHttpContext CreateHttpContext(string method, string body)
    {
        var httpContext = new DefaultHttpContext();
        httpContext.Request.Method = method;
        var requestBody = body;
        var bytes = Encoding.UTF8.GetBytes(requestBody);
        httpContext.Request.Body = new MemoryStream(bytes);
        httpContext.Request.Body.Seek(0, SeekOrigin.Begin);
        return httpContext;
    }

    private static RequestBodyLoggingMiddleware CreateSut(RequestDelegate nextRequestDelegate)
    {
        return new RequestBodyLoggingMiddleware(nextRequestDelegate);
    }
}
