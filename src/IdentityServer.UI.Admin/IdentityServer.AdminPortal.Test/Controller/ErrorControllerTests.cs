// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using AutoFixture;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using NSubstitute;
using IdentityServer.AdminPortal.Server.Controllers;

namespace IdentityServer.AdminPortal.Test.Controller;

[TestFixture]
public class ErrorControllerTests : ControllerTestBase
{
    private ErrorController _controller;
    private IHostEnvironment _mockHostEnvironment;
    private Fixture _fixture;

    [SetUp]
    public void SetUp()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ErrorController>();
        });

        _fixture = new Fixture();
        _mockHostEnvironment = Substitute.For<IHostEnvironment>();
        _controller = new ErrorController();
    }

    [Test]
    public void HandleError_ReturnsProblemDetails()
    {
        // Act
        var result = _controller.HandleError();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.TypeOf<ObjectResult>());
            var objectResult = result as ObjectResult;
            Assert.That(objectResult!.StatusCode, Is.EqualTo(500));
            Assert.That(objectResult.Value, Is.TypeOf<ProblemDetails>());
        }
    }

    [TestCase("Staging")]
    [TestCase("Production")]
    public void HandleErrorDevelopment_WhenNotDevelopmentEnvironment_ReturnsNotFound(string environment)
    {
        // Arrange
        _mockHostEnvironment.EnvironmentName.Returns(environment);

        // Act
        var result = _controller.HandleErrorDevelopment(_mockHostEnvironment);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.TypeOf<NotFoundResult>());
        }
    }

    [TestCase("Development")]
    [TestCase("development")]
    public void HandleErrorDevelopment_WhenDevelopmentEnvironmentAndExceptionExists_ReturnsProblemWithDetails(string environment)
    {
        // Arrange
        _mockHostEnvironment.EnvironmentName.Returns(environment);
        var exception = new InvalidOperationException("message");
        SetupHttpContextWithException(exception);

        // Act
        var result = _controller.HandleErrorDevelopment(_mockHostEnvironment);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.TypeOf<ObjectResult>());
            var objectResult = result as ObjectResult;
            Assert.That(objectResult.StatusCode, Is.EqualTo(500));
            Assert.That(objectResult.Value, Is.TypeOf<ProblemDetails>());

            var problemDetails = objectResult.Value as ProblemDetails;
            Assert.That(problemDetails.Title, Is.EqualTo(exception.Message));
        }
    }

    private void SetupHttpContextWithException(Exception exception)
    {
        var exceptionFeature = Substitute.For<IExceptionHandlerFeature>();
        exceptionFeature.Error.Returns(exception);

        var httpContext = new DefaultHttpContext();
        httpContext.Features.Set(exceptionFeature);
        _controller.ControllerContext = new ControllerContext
        {
            HttpContext = httpContext
        };
    }
}
