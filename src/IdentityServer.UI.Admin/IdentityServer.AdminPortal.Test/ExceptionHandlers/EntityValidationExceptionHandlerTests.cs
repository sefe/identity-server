using Microsoft.AspNetCore.Http;
using NSubstitute;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.ExceptionHandlers;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.ExceptionHandlers;

[TestFixture]
public class EntityValidationExceptionHandlerTests
{
    private EntityValidationExceptionHandler _sut;
    private IProblemDetailsService _problemDetailsService;
    private MockLogger<EntityValidationExceptionHandler> _logger;
    private HttpContext _httpContext;

    [SetUp]
    public void SetUp()
    {
        _problemDetailsService = Substitute.For<IProblemDetailsService>();
        _logger = new MockLogger<EntityValidationExceptionHandler>();
        _httpContext = new DefaultHttpContext();
        _sut = new EntityValidationExceptionHandler(_problemDetailsService, _logger);
    }

    [TestCaseSource(nameof(GetExceptions))]
    public async Task TryHandleAsync_WithEntityValidationException_CallsProblemDetailsServiceWithCorrectContext(EntityValidationException exception
        )
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
            ctx.ProblemDetails.Title == "Entity is invalid"));
    }

    private static IEnumerable<TestCaseData> GetExceptions()
    {
        yield return new TestCaseData(new object[] { new EntityValidationException() });
        yield return new TestCaseData(new object[] { new EntityValidationException("test") });
        yield return new TestCaseData(new object[] { new EntityValidationException("test", new Exception("inner")) });
    }
}
