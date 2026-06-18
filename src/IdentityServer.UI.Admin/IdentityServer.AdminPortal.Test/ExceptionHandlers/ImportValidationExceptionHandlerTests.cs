using Microsoft.AspNetCore.Http;
using NSubstitute;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.ExceptionHandlers;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.ExceptionHandlers;

[TestFixture]
public class ImportValidationExceptionHandlerTests
{
    private ImportValidationExceptionHandler _sut;
    private IProblemDetailsService _problemDetailsService;
    private MockLogger<ImportValidationExceptionHandler> _logger;
    private HttpContext _httpContext;

    [SetUp]
    public void SetUp()
    {
        _problemDetailsService = Substitute.For<IProblemDetailsService>();
        _logger = new MockLogger<ImportValidationExceptionHandler>();
        _httpContext = new DefaultHttpContext();
        _sut = new ImportValidationExceptionHandler(_problemDetailsService, _logger);
    }

    [TestCaseSource(nameof(GetExceptions))]
    public async Task TryHandleAsync_WithImportValidationException_CallsProblemDetailsServiceWithCorrectContext(ImportValidationException exception)
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
            ctx.ProblemDetails.Title == "The import data is invalid."));
    }

    private static IEnumerable<TestCaseData> GetExceptions()
    {
        yield return new TestCaseData(new object[] { new ImportValidationException() });
        yield return new TestCaseData(new object[] { new ImportValidationException("test", new Abstraction.DTO.Import.OperationStatus()) });
        yield return new TestCaseData(new object[] { new ImportValidationException("test", new Exception("inner")) });
    }
}
