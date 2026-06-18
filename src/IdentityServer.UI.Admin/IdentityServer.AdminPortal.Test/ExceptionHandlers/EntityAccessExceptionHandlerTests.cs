using System.Security.Claims;
using System.Security.Principal;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.ExceptionHandlers;
using IdentityServer.Tests.Common;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.AdminPortal.Test.ExceptionHandlers;

/// <summary>
/// Tests for BasicExceptionHandler functionality and for EntityAccessExceptionHandler specifics.
/// </summary>
[TestFixture]
public class EntityAccessExceptionHandlerTests
{
    private EntityAccessExceptionHandler _sut;
    private IProblemDetailsService _problemDetailsService;
    private MockLogger<EntityAccessExceptionHandler> _logger;
    private DefaultHttpContext _httpContext;

    [SetUp]
    public void SetUp()
    {
        _problemDetailsService = Substitute.For<IProblemDetailsService>();
        _logger = new MockLogger<EntityAccessExceptionHandler>();
        _httpContext = new DefaultHttpContext();
        _sut = new EntityAccessExceptionHandler(_problemDetailsService, _logger);
    }

    private static Claim CreateOidClaim(string id) => new(ClaimNames.UserObjectId, id);
    private static ClaimsPrincipal CreatePrincipal(string id, bool withIdentityName = true, bool withEmail = true)
    {
        var identity = Substitute.For<IIdentity>();
        if (withIdentityName)
        {
            identity.Name.Returns(id + " Name");
        }

        var claims = withEmail ? new[] { CreateOidClaim(id + "id"), new Claim(ClaimNames.UserEmail, id + "@example.com") }
            : new[] { CreateOidClaim(id + "id") };
        var claimsIdentity = new ClaimsIdentity(identity, claims);

        return new ClaimsPrincipal(claimsIdentity);
    }

    // ---- Common -----
    [TestCase(true)]
    [TestCase(false)]
    public async Task TryHandleAsync_Base_WithCorrectException_ReturnsDependencyResult(bool expectedResult)
    {
        // Arrange
        var exception = new EntityAccessException(CreatePrincipal("user123"), "ApiResource", EntityAccessType.Read);
        var cancellationToken = CancellationToken.None;

        _problemDetailsService.TryWriteAsync(Arg.Any<ProblemDetailsContext>()).Returns(expectedResult);

        // Act
        var result = await _sut.TryHandleAsync(_httpContext, exception, cancellationToken);

        // Assert
        Assert.That(result, Is.EqualTo(expectedResult));
    }

    [Test]
    public async Task TryHandleAsync_Base_WithCorrectException_CallsProblemDetailsServiceWithCorrectContext()
    {
        // Arrange
        var exception = new EntityAccessException(CreatePrincipal("user123"), "ApiResource", EntityAccessType.Read);
        var cancellationToken = CancellationToken.None;

        _problemDetailsService.TryWriteAsync(Arg.Any<ProblemDetailsContext>()).Returns(true);

        // Act
        await _sut.TryHandleAsync(_httpContext, exception, cancellationToken);

        // Assert
        await _problemDetailsService.Received(1).TryWriteAsync(Arg.Is<ProblemDetailsContext>(ctx =>
            ctx.HttpContext == _httpContext &&
            ctx.ProblemDetails.Detail == exception.Message &&
            ctx.ProblemDetails.Instance == _httpContext.TraceIdentifier &&
            ctx.Exception == exception));
    }

    [Test]
    public async Task TryHandleAsync_Base_WithCorrectException_LogsWarning()
    {
        // Arrange
        var exception = new EntityAccessException(CreatePrincipal("user123"), "ApiResource", EntityAccessType.Read);
        var cancellationToken = CancellationToken.None;
        _httpContext.Request.Method = "GET";
        _httpContext.Request.Path = "/api/test";

        _problemDetailsService.TryWriteAsync(Arg.Any<ProblemDetailsContext>()).Returns(true);

        // Act
        await _sut.TryHandleAsync(_httpContext, exception, cancellationToken);

        // Assert
        Assert.That(_logger.CapturedWarnings, Has.Count.EqualTo(1));
        Assert.That(_logger.CapturedWarnings[0], Does.Contain("Invalid GET Request at /api/test"));
    }

    [Test]
    public async Task TryHandleAsync_Base_WithExceptionHandlerPathFeature_UsesOriginalPath()
    {
        // Arrange
        var exception = new EntityAccessException(CreatePrincipal("user123"), "ApiResource", EntityAccessType.Read);
        var cancellationToken = CancellationToken.None;
        var originalPath = "/api/original";

        var pathFeature = Substitute.For<IExceptionHandlerPathFeature>();
        pathFeature.Path.Returns(originalPath);
        _httpContext.Features.Set(pathFeature);
        _httpContext.Request.Method = "POST";
        _httpContext.Request.Path = "/error";

        _problemDetailsService.TryWriteAsync(Arg.Any<ProblemDetailsContext>()).Returns(true);

        // Act
        await _sut.TryHandleAsync(_httpContext, exception, cancellationToken);

        // Assert
        Assert.That(_logger.CapturedWarnings, Has.Count.EqualTo(1));
        Assert.That(_logger.CapturedWarnings[0], Does.Contain($"Invalid POST Request at {originalPath}"));
    }

    [Test]
    public async Task TryHandleAsync_WithDifferentExceptionType_DoesnotProcess()
    {
        // Arrange
        var exception = new ArgumentNullException("test");
        var cancellationToken = CancellationToken.None;

        // Act
        var result = await _sut.TryHandleAsync(_httpContext, exception, cancellationToken);

        // Assert
        await _problemDetailsService.DidNotReceive().TryWriteAsync(Arg.Any<ProblemDetailsContext>());
        Assert.That(result, Is.False);
    }

    // ---- Specific ----

    [TestCaseSource(nameof(GetExceptions))]
    public async Task TryHandleAsync_WithEntityAccessException_CallsProblemDetailsServiceWithCorrectContext(EntityAccessException exception, string user)
    {
        // Arrange
        var cancellationToken = CancellationToken.None;

        _problemDetailsService.TryWriteAsync(Arg.Any<ProblemDetailsContext>()).Returns(true);

        // Act
        await _sut.TryHandleAsync(_httpContext, exception, cancellationToken);

        // Assert
        await _problemDetailsService.Received(1).TryWriteAsync(Arg.Is<ProblemDetailsContext>(ctx =>
            ctx.HttpContext.Response.StatusCode == StatusCodes.Status403Forbidden &&
            ctx.ProblemDetails.Status == StatusCodes.Status403Forbidden &&
            ctx.ProblemDetails.Detail == exception.Message &&
            ctx.ProblemDetails.Detail.Contains(user) &&
            ctx.ProblemDetails.Detail.Contains(exception.Entity ?? "") &&
            (!exception.Access.HasValue || ctx.ProblemDetails.Detail.Contains(exception.Access.ToString())) &&
            ctx.ProblemDetails.Title == "The user is not authorized to access the requested entity."));
    }

    private static IEnumerable<TestCaseData> GetExceptions()
    {
        yield return new TestCaseData(new object[] { new EntityAccessException(), "" });
        yield return new TestCaseData(new object[] { new EntityAccessException(CreatePrincipal("user123"), "ApiResource", EntityAccessType.Read, "reason"), "user123 Name" });
        yield return new TestCaseData(new object[] { new EntityAccessException(CreatePrincipal("user123", withIdentityName: false, withEmail: true), "ApiResource", EntityAccessType.Read, "reason", new InvalidOperationException("fake")), "user123@example.com" });
        yield return new TestCaseData(new object[] { new EntityAccessException(CreatePrincipal("user123", withIdentityName: false, withEmail: false), "ApiResource", EntityAccessType.Read), "user123id" });
        yield return new TestCaseData(new object[] { new EntityAccessException(CreatePrincipal("user123"), "ApiResource", EntityAccessType.Create, new InvalidCastException("boo")), "user123id" });
    }
}
