// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Http;
using NSubstitute;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.ExceptionHandlers;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.ExceptionHandlers;

[TestFixture]
public class InvalidSearchValueExceptionHandlerTests
{
    private InvalidSearchValueExceptionHandler _sut;
    private IProblemDetailsService _problemDetailsService;
    private MockLogger<InvalidSearchValueExceptionHandler> _logger;
    private HttpContext _httpContext;

    [SetUp]
    public void SetUp()
    {
        _problemDetailsService = Substitute.For<IProblemDetailsService>();
        _logger = new MockLogger<InvalidSearchValueExceptionHandler>();
        _httpContext = new DefaultHttpContext();
        _sut = new InvalidSearchValueExceptionHandler(_problemDetailsService, _logger);
    }

    [TestCaseSource(nameof(GetExceptions))]
    public async Task TryHandleAsync_WithInvalidSearchValueException_CallsProblemDetailsServiceWithCorrectContext(InvalidSearchValueException exception)
    {
        // Arrange
        var cancellationToken = CancellationToken.None;

        _problemDetailsService.TryWriteAsync(Arg.Any<ProblemDetailsContext>()).Returns(true);

        // Act
        await _sut.TryHandleAsync(_httpContext, exception, cancellationToken);

        // Assert
        await _problemDetailsService.Received(1).TryWriteAsync(Arg.Is<ProblemDetailsContext>(ctx =>
            ctx.HttpContext.Response.StatusCode == StatusCodes.Status400BadRequest &&
            ctx.ProblemDetails.Status == StatusCodes.Status400BadRequest &&
            ctx.ProblemDetails.Detail == exception.Message &&
            ctx.ProblemDetails.Title == "The provided search term is invalid"));
    }

    private static IEnumerable<TestCaseData> GetExceptions()
    {
        yield return new TestCaseData(new object[] { new InvalidSearchValueException() });
        yield return new TestCaseData(new object[] { new InvalidSearchValueException("test") });
        yield return new TestCaseData(new object[] { new InvalidSearchValueException("test", new Exception("inner")) });
    }
}
