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
public class GroupControllerTests : ControllerTestBase
{
    private GroupController _controller;
    private IEntraGroupService _mockEntraGroupService;
    private Fixture _fixture;

    [SetUp]
    public async Task SetUp()
    {
        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<GroupController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
        });

        await Setup(provider);

        _fixture = new Fixture();
        _mockEntraGroupService = Substitute.For<IEntraGroupService>();
        _controller = new GroupController(_mockEntraGroupService);
    }

    [TestCase("abc")]
    [TestCase("GroupAdmin")]
    [TestCase("IT-Support")]
    public async Task GetGroupsByDisplayName_WithValidSearchStrings_ReturnsGroupResponse(string searchString)
    {
        // Arrange
        var skipToken = _fixture.Create<string>();
        var expectedGroupResponse = _fixture.Create<GroupResponse>();
        _mockEntraGroupService.GetGroupsByDisplayNameAsync(searchString, skipToken).Returns(expectedGroupResponse);

        // Act
        var result = await _controller.Call_GetGroupsByDisplayNameAsync(searchString, skipToken, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.EqualTo(expectedGroupResponse));
        }
        await _mockEntraGroupService.Received(1).GetGroupsByDisplayNameAsync(searchString, skipToken);
    }

    [Test]
    public async Task GetGroupsByDisplayName_WithNullSkipToken_ReturnsGroupResponse()
    {
        // Arrange
        var searchString = _fixture.Create<string>();
        string skipToken = null;
        var expectedGroupResponse = _fixture.Create<GroupResponse>();
        _mockEntraGroupService.GetGroupsByDisplayNameAsync(searchString, skipToken).Returns(expectedGroupResponse);

        // Act
        var result = await _controller.Call_GetGroupsByDisplayNameAsync(searchString, skipToken, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.EqualTo(expectedGroupResponse));
        }
        await _mockEntraGroupService.Received(1).GetGroupsByDisplayNameAsync(searchString, skipToken);
    }

    [TestCase("1")]
    [TestCase("ab")]
    [TestCase(" ")]
    [TestCase("")]
    [TestCase("  q")]
    [TestCase("q  ")]
    public async Task GetGroupsByDisplayName_WithSearchStringInvalid_ReturnsBadRequest(string searchString)
    {
        // Arrange
        var skipToken = _fixture.Create<string>();

        // Act
        SetControllerContext(_controller, Admin);
        var result = await _controller.GetGroupsByDisplayName(searchString, skipToken);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Result, Is.TypeOf<BadRequestObjectResult>());
            Assert.That(((BadRequestObjectResult)result.Result).Value, Is.EqualTo(SearchFormModel.MinSearchSymbolsErrorMessage));
        }
        await _mockEntraGroupService.DidNotReceive().GetGroupsByDisplayNameAsync(Arg.Any<string>(), Arg.Any<string>());
    }

    [Test]
    public async Task GetGroupsByDisplayName_WithNoGroupsFound_ReturnsEmptyResponse()
    {
        // Arrange
        var searchString = _fixture.Create<string>();
        var skipToken = _fixture.Create<string>();
        var expectedGroupResponse = _fixture.Build<GroupResponse>()
            .With(x => x.Groups, new List<Group>())
            .Create();
        _mockEntraGroupService.GetGroupsByDisplayNameAsync(searchString, skipToken).Returns(expectedGroupResponse);

        // Act
        var result = await _controller.Call_GetGroupsByDisplayNameAsync(searchString, skipToken, Admin);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.EqualTo(expectedGroupResponse));
        }
        await _mockEntraGroupService.Received(1).GetGroupsByDisplayNameAsync(searchString, skipToken);
    }

    [Test]
    public async Task GetGroupsByDisplayName_WhenServiceThrowsException_PropagatesException()
    {
        // Arrange
        var searchString = _fixture.Create<string>();
        var skipToken = _fixture.Create<string>();
        var expectedException = _fixture.Create<InvalidOperationException>();
        _mockEntraGroupService.GetGroupsByDisplayNameAsync(searchString, skipToken).Throws(expectedException);

        // Act & Assert
        var exception = Assert.ThrowsAsync<InvalidOperationException>(() => _controller.Call_GetGroupsByDisplayNameAsync(searchString, skipToken, Admin));
        Assert.That(exception.Message, Is.EqualTo(expectedException.Message));
        await _mockEntraGroupService.Received(1).GetGroupsByDisplayNameAsync(searchString, skipToken);
    }
}
