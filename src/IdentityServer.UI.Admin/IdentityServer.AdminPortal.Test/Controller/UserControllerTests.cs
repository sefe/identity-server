using AutoFixture;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.AdminPortal.Web.Services.Search;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

[TestFixture]
public class UserControllerTests : ControllerTestBase
{
    private UserController _controller;
    private IEntraUserService _mockEntraUserService;
    private Fixture _fixture;

    [SetUp]
    public async Task SetUp()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<UserController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
        });

        await Setup(provider);

        _fixture = new Fixture();
        _mockEntraUserService = Substitute.For<IEntraUserService>();
        _controller = new UserController(_mockEntraUserService);
    }

    [TestCase("")]
    [TestCase(" ")]
    [TestCase("123")]
    [TestCase(null!)]
    public async Task GetUserById_WithAnyId_ReturnsUserResponse(string userId)
    {
        // Arrange
        var expectedUserResponse = _fixture.Create<UserResponse>();
        _mockEntraUserService.GetUserByObjectIdAsync(userId).Returns(expectedUserResponse);

        // Act
        var result = await _controller.Call_GetUserByIdAsync(userId, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.EqualTo(expectedUserResponse));
        }
        await _mockEntraUserService.Received(1).GetUserByObjectIdAsync(userId);
    }

    [Test]
    public void GetUserById_WhenServiceThrowsException_PropagatesException()
    {
        // Arrange
        var expectedException = _fixture.Create<InvalidOperationException>();
        _mockEntraUserService.GetUserByObjectIdAsync(Arg.Any<string>()).ThrowsAsync(expectedException);
        SetControllerContext(_controller, Admin);

        // Act & Assert
        var exception = Assert.ThrowsAsync<InvalidOperationException>(() => _controller.GetUserById("userId"));
        Assert.That(exception.Message, Is.EqualTo(expectedException.Message));
    }

    [TestCase("string")]
    [TestCase("123456")]
    [TestCase("o'connor")]
    public async Task SearchUsersByDisplayName_WithValidSearchString_ReturnsUserResponse(string searchString)
    {
        // Arrange
        var expectedUserResponse = _fixture.Create<UserResponse>();
        _mockEntraUserService.GetUsersByDisplayNameAsync(Arg.Any<string>()).Returns(expectedUserResponse);

        // Act
        var result = await _controller.Call_SearchUsersByDisplayNameAsync(searchString, Admin);

        // Assert
        Assert.That(result, Is.EqualTo(expectedUserResponse));
        await _mockEntraUserService.Received(1).GetUsersByDisplayNameAsync(searchString);
    }

    [Test]
    public async Task SearchUsersByDisplayName_WithMinimumValidLength_ReturnsUserResponse()
    {
        // Arrange
        var searchString = "abc"; // Exactly 3 characters (minimum)
        var expectedUserResponse = _fixture.Create<UserResponse>();
        _mockEntraUserService.GetUsersByDisplayNameAsync(Arg.Any<string>()).Returns(expectedUserResponse);

        // Act
        var result = await _controller.Call_SearchUsersByDisplayNameAsync(searchString, Admin);

        // Assert
        Assert.That(result, Is.EqualTo(expectedUserResponse));
        await _mockEntraUserService.Received(1).GetUsersByDisplayNameAsync(searchString);
    }

    [TestCase("1")]
    [TestCase("ab")]
    [TestCase(" ")]
    [TestCase("")]
    [TestCase("  q")]
    [TestCase("q  ")]
    public async Task SearchUsersByDisplayName_WithSearchStringTooShort_ReturnsBadRequest(string searchString)
    {
        // Act
        SetControllerContext(_controller, Admin);
        var result = await _controller.SearchUsersByDisplayName(searchString);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Result, Is.TypeOf<BadRequestObjectResult>());
            Assert.That(((BadRequestObjectResult)result.Result).Value, Is.EqualTo(SearchFormModel.MinSearchSymbolsErrorMessage));
        }
        await _mockEntraUserService.DidNotReceive().GetUsersByDisplayNameAsync(Arg.Any<string>());
    }

    [Test]
    public async Task SearchUsersByDisplayName_TrimsSearchString()
    {
        // Arrange
        var searchString = "   abc   ";
        var trimmedSearchString = "abc";
        var expectedUserResponse = _fixture.Create<UserResponse>();
        _mockEntraUserService.GetUsersByDisplayNameAsync(Arg.Any<string>()).Returns(expectedUserResponse);

        // Act
        var result = await _controller.Call_SearchUsersByDisplayNameAsync(searchString, Admin);

        // Assert
        Assert.That(result, Is.EqualTo(expectedUserResponse));
        await _mockEntraUserService.Received(1).GetUsersByDisplayNameAsync(trimmedSearchString);
    }

    [Test]
    public async Task SearchUsersByDisplayName_WhenServiceThrowsException_PropagatesException()
    {
        // Arrange
        var searchString = "abcd";
        var expectedException = _fixture.Create<InvalidOperationException>();
        _mockEntraUserService.GetUsersByDisplayNameAsync(searchString).Throws(expectedException);
        SetControllerContext(_controller, Admin);

        // Act & Assert
        var exception = Assert.ThrowsAsync<InvalidOperationException>(() => _controller.SearchUsersByDisplayName(searchString));
        Assert.That(exception.Message, Is.EqualTo(expectedException.Message));
        await _mockEntraUserService.Received(1).GetUsersByDisplayNameAsync(searchString);
    }
}
