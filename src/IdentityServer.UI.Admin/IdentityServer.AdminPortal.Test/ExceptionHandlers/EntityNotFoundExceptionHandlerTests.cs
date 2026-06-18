using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using NSubstitute;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.ExceptionHandlers;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.ExceptionHandlers;

[TestFixture]
public class EntityNotFoundExceptionHandlerTests
{
    private EntityNotFoundExceptionHandler _sut;
    private IProblemDetailsService _problemDetailsService;
    private MockLogger<EntityNotFoundExceptionHandler> _logger;
    private HttpContext _httpContext;

    [SetUp]
    public void SetUp()
    {
        _problemDetailsService = Substitute.For<IProblemDetailsService>();
        _logger = new MockLogger<EntityNotFoundExceptionHandler>();
        _httpContext = new DefaultHttpContext();
        _sut = new EntityNotFoundExceptionHandler(_problemDetailsService, _logger);
    }

    [TestCaseSource(nameof(GetExceptions))]
    public async Task TryHandleAsync_WithEntityNotFoundException_CallsProblemDetailsServiceWithCorrectContext(EntityNotFoundException exception)
    {
        // Arrange
        var cancellationToken = CancellationToken.None;

        _problemDetailsService.TryWriteAsync(Arg.Any<ProblemDetailsContext>()).Returns(true);

        // Act
        await _sut.TryHandleAsync(_httpContext, exception, cancellationToken);

        // Assert
        await _problemDetailsService.Received(1).TryWriteAsync(Arg.Is<ProblemDetailsContext>(ctx =>
            ctx.HttpContext.Response.StatusCode == StatusCodes.Status404NotFound  &&
            ctx.ProblemDetails.Status == StatusCodes.Status404NotFound &&
            ctx.ProblemDetails.Detail == exception.Message &&
            ctx.ProblemDetails.Title == "The requested entity was not found"));
    }

    private static IEnumerable<TestCaseData> GetExceptions()
    {
       yield return new TestCaseData(new object[] { new EntityNotFoundException() });
       yield return new TestCaseData(new object[] { new EntityNotFoundException("test") });
       yield return new TestCaseData(new object[] { new EntityNotFoundException("test", new Exception("inner")) });
    }
}
