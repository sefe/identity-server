using Microsoft.AspNetCore.Http;
using NSubstitute;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.ExceptionHandlers;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.ExceptionHandlers;

[TestFixture]
public class UserClaimExceptionHandlerTests
{
    private UserClaimExceptionHandler _sut;
    private IProblemDetailsService _problemDetailsService;
    private MockLogger<UserClaimExceptionHandler> _logger;
    private HttpContext _httpContext;

    [SetUp]
    public void SetUp()
    {
        _problemDetailsService = Substitute.For<IProblemDetailsService>();
        _logger = new MockLogger<UserClaimExceptionHandler>();
        _httpContext = new DefaultHttpContext();
        _sut = new UserClaimExceptionHandler(_problemDetailsService, _logger);
    }

    [TestCaseSource(nameof(GetExceptions))]
    public async Task TryHandleAsync_WithUserClaimException_CallsProblemDetailsServiceWithCorrectContext(UserClaimException exception)
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
            ctx.ProblemDetails.Title == "The logged in user lacks mandatory profile information. A re-login may fix this issue."));
    }

    private static IEnumerable<TestCaseData> GetExceptions()
    {
        yield return new TestCaseData(new object[] { new UserClaimException() });
        yield return new TestCaseData(new object[] { new UserClaimException("claim", "message") });
        yield return new TestCaseData(new object[] { new UserClaimException("claim", "message", new Exception("inner")) });
    }
}
