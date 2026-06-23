// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NSubstitute;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.Tests.Common;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.AdminPortal.Web.Tests.Services;

[TestFixture]
public class SystemOwnerServiceTests
{
    private const string _userOId = "current-user";
    private const string _otherUserOId = "other-user";

    private IConfirmationService _mockConfirmationService;
    private MockHttpMessageHandler _mockHandler;
    private HttpClient _mockHttpClient;
    private IAdminApiService _adminApiService;
    private SystemOwnerService _sut;

    [SetUp]
    public void SetUp()
    {
        _mockConfirmationService = Substitute.For<IConfirmationService>();

        _mockHandler = new MockHttpMessageHandler();
        _mockHttpClient = new HttpClient(_mockHandler)
        {
            BaseAddress = new Uri("https://localhost/")
        };

        var mockHttpClientFactory = Substitute.For<IHttpClientFactory>();
        mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(_mockHttpClient);
        _adminApiService = new AdminApiService(mockHttpClientFactory);

        _sut = new SystemOwnerService(_mockConfirmationService, _adminApiService);
    }

    [TearDown]
    public void TearDown()
    {
        _mockHttpClient?.Dispose();
        _mockHandler?.Dispose();
    }

    #region ShowContactsPopup - SystemPermissionShortDtoRead

    [Test]
    public async Task ShowContactsPopup_WithSystemPermissionShortDtoRead_CallsConfirmationService()
    {
        // Arrange
        var sysPermission = new SystemPermissionShortDtoRead
        {
            Name = "TestPermission",
            Description = "Test Description",
            OwnersList = new() { "Owner1", "Owner2" },
        };

        // Act
        await _sut.ShowContactsPopup(sysPermission);

        // Assert
        await _mockConfirmationService.Received(1).ConfirmAsync(
            "System Permission Owners",
            "Access to this System Permission can be granted by: Owner1, Owner2",
            false);
    }

    [Test]
    public async Task ShowContactsPopup_WithSystemPermissionShortDtoRead_WithEmptyOwners_CallsConfirmationService()
    {
        // Arrange
        var sysPermission = new SystemPermissionShortDtoRead
        {
            Name = "TestPermission",
            Description = "Test Description",
            OwnersList = new(),
        };

        // Act
        await _sut.ShowContactsPopup(sysPermission);

        // Assert
        await _mockConfirmationService.Received(1).ConfirmAsync(
            "System Permission Owners",
            "The access to this System Permission can only be granted by IdentityServer support personnel.",
            false);
    }

    [Test]
    public async Task ShowContactsPopup_WithSystemPermissionShortDtoRead_WithNullOwners_CallsConfirmationService()
    {
        // Arrange
        var sysPermission = new SystemPermissionShortDtoRead
        {
            Name = "TestPermission",
            Description = "Test Description",
            OwnersList = null
        };

        // Act
        await _sut.ShowContactsPopup(sysPermission);

        // Assert
        await _mockConfirmationService.Received(1).ConfirmAsync(
            "System Permission Owners",
            "The access to this System Permission can only be granted by IdentityServer support personnel.",
            false);
    }

    #endregion

    #region ShowContactsPopup - SystemPermissionEnvironmentDtoRead

    [Test]
    public async Task ShowContactsPopup_WithSystemPermissionEnvironmentDtoRead_CallsConfirmationService()
    {
        // Arrange
        var sysPermissionEnvironment = new SystemPermissionEnvironmentDtoRead
        {
            Environment = "Production",
            Permissions = new List<SystemPermissionRoleDtoRead>
            {
                new() {
                    Id = 1,
                    OId = "oid-1",
                    Name = "EnvOwner1",
                    SystemPermissionEnvironmentId = 1,
                    RoleType = SystemPermissionRoleType.Writer
                },
                new() {
                    Id = 2,
                    OId = "oid-2",
                    Name = "EnvOwner2",
                    SystemPermissionEnvironmentId = 1,
                    RoleType = SystemPermissionRoleType.Writer
                }
            }
        };

        // Act
        await _sut.ShowContactsPopup(sysPermissionEnvironment);

        // Assert
        await _mockConfirmationService.Received(1).ConfirmAsync(
            "System Permission Environment Owners",
            "Access to this System Permission Environment can be granted by: EnvOwner1, EnvOwner2",
            false);
    }

    [Test]
    public async Task ShowContactsPopup_WithSystemPermissionEnvironmentDtoRead_WithEmptyOwners_CallsConfirmationService()
    {
        // Arrange
        var sysPermissionEnvironment = new SystemPermissionEnvironmentDtoRead
        {
            Environment = "Production",
            Permissions = new List<SystemPermissionRoleDtoRead>()
        };

        // Act
        await _sut.ShowContactsPopup(sysPermissionEnvironment);

        // Assert
        await _mockConfirmationService.Received(1).ConfirmAsync(
            "System Permission Environment Owners",
            "The access to this System Permission Environment can only be granted by IdentityServer support personnel.",
            false);
    }

    #endregion

    #region ShowContactsPopup - int envId

    [Test]
    public async Task ShowContactsPopup_WithEnvId_WithOwners_CallsConfirmationServiceWithOwnersList()
    {
        // Arrange
        var owners = new[] { "Owner1", "Owner2", "Owner3" };
        _mockHandler.SetResponse(System.Net.HttpStatusCode.OK, System.Text.Json.JsonSerializer.Serialize(owners));

        // Act
        await _sut.ShowContactsPopup(1);

        // Assert
        await _mockConfirmationService.Received(1).ConfirmAsync(
            "System Permission Environment Owners",
            "Access to this System Permission Environment can be granted by: Owner1, Owner2, Owner3",
            false);
    }

    [Test]
    public async Task ShowContactsPopup_WithEnvId_WithNoOwners_CallsConfirmationServiceWithDefaultMessage()
    {
        // Arrange
        _mockHandler.SetResponse(System.Net.HttpStatusCode.OK, System.Text.Json.JsonSerializer.Serialize(Array.Empty<string>()));

        // Act
        await _sut.ShowContactsPopup(1);

        // Assert
        await _mockConfirmationService.Received(1).ConfirmAsync(
            "System Permission Environment Owners",
            "The access to this System Permission Environment can only be granted by IdentityServer support personnel.",
            false);
    }

    [Test]
    public async Task ShowContactsPopup_WithEnvId_WithNullOwners_CallsConfirmationServiceWithDefaultMessage()
    {
        // Arrange
        _mockHandler.SetResponse(System.Net.HttpStatusCode.OK, null);

        // Act
        await _sut.ShowContactsPopup(1);

        // Assert
        await _mockConfirmationService.Received(1).ConfirmAsync(
            "System Permission Environment Owners",
            "The access to this System Permission Environment can only be granted by IdentityServer support personnel.",
            false);
    }

    #endregion

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfLastFullWriter_WithAdmin_BlocksRemovalAndReturnsFalse()
    {
        // Arrange
        var systemPermission = CreateSystemPermissionWithFullWriter(_userOId);
        var role = systemPermission.Environments[0].Permissions[0];
        var roleEnvironment = systemPermission.Environments[0];

        _mockConfirmationService.ConfirmAsync(
            SystemOwnerService.FullWriterLastDeletionBlock.Title,
            Arg.Any<string>(),
            false)
            .Returns(false);

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            await _mockConfirmationService.Received(1).ConfirmAsync(
                SystemOwnerService.FullWriterLastDeletionBlock.Title,
                SystemOwnerService.FullWriterLastDeletionBlock.FormatMessage(role.Name),
                false);
        }
    }

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfLastFullWriter_WithNonAdmin_BlocksRemovalAndReturnsFalse()
    {
        // Arrange
        var systemPermission = CreateSystemPermissionWithFullWriter(_userOId);
        var role = systemPermission.Environments[0].Permissions[0];
        var roleEnvironment = systemPermission.Environments[0];

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            await _mockConfirmationService.Received(1).ConfirmAsync(
                SystemOwnerService.FullWriterLastDeletionBlock.Title,
                SystemOwnerService.FullWriterLastDeletionBlock.FormatMessage(role.Name),
                false);
        }
    }

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfFullWriter_WithOtherFullWriters_RequestsConfirmation()
    {
        // Arrange
        var systemPermission = CreateSystemPermissionWithTwoFullWriters(_userOId, _otherUserOId);
        var role = systemPermission.Environments[0].Permissions[0];
        var roleEnvironment = systemPermission.Environments[0];

        _mockConfirmationService.ConfirmAsync(
            SystemOwnerService.FullWriterDeletionConfirmation.Title,
            Arg.Any<string>())
            .Returns(true);

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            await _mockConfirmationService.Received(1).ConfirmAsync(
                SystemOwnerService.FullWriterDeletionConfirmation.Title,
                SystemOwnerService.FullWriterDeletionConfirmation.FormatMessage(role.Name, systemPermission.Name));
        }
    }

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfFullWriter_WithOtherFullWriters_WhenUserDeclinesConfirmation_ReturnsFalse()
    {
        // Arrange
        var systemPermission = CreateSystemPermissionWithTwoFullWriters(_userOId, _otherUserOId);
        var role = systemPermission.Environments[0].Permissions[0];
        var roleEnvironment = systemPermission.Environments[0];

        _mockConfirmationService.ConfirmAsync(
            SystemOwnerService.FullWriterDeletionConfirmation.Title,
            Arg.Any<string>())
            .Returns(false);

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        Assert.That(result, Is.False);
    }

    #region CheckUserAssignmentRemovalConditions - Writer Access Removal

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfWriter_WithLastWriterAssignment_RequestsSystemPermissionAccessRemovalConfirmation()
    {
        // Arrange
        var systemPermission = CreateSystemPermissionWithSingleWriterInEachEnvironment(_userOId, _otherUserOId);
        var role = systemPermission.Environments[0].Permissions[0];
        var roleEnvironment = systemPermission.Environments[0];

        _mockConfirmationService.ConfirmAsync(
            SystemOwnerService.UserSystemPermissionAccessRemovalConfirmation.Title,
            Arg.Any<string>())
            .Returns(true);

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            await _mockConfirmationService.Received(1).ConfirmAsync(
                SystemOwnerService.UserSystemPermissionAccessRemovalConfirmation.Title,
                SystemOwnerService.UserSystemPermissionAccessRemovalConfirmation.FormatMessage(role, systemPermission.Name));
        }
    }

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfWriter_WithLastWriterAssignment_WhenUserDeclinesConfirmation_ReturnsFalse()
    {
        // Arrange
        var systemPermission = CreateSystemPermissionWithSingleWriterInEachEnvironment(_userOId, _otherUserOId);
        var role = systemPermission.Environments[0].Permissions[0];
        var roleEnvironment = systemPermission.Environments[0];

        _mockConfirmationService.ConfirmAsync(
            SystemOwnerService.UserSystemPermissionAccessRemovalConfirmation.Title,
            Arg.Any<string>())
            .Returns(false);

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfWriter_WithMultipleWriterAssignments_RequestsEnvironmentAccessRemovalConfirmation()
    {
        // Arrange
        // _otherUser is neither a FullWriter, nor the last Writer.
        var systemPermission = new SystemPermissionDtoReadBuilder()
            .AddEnvironment("Development")
                .AddPermission(_userOId, "Test User 1", SystemPermissionRoleType.Writer)
                .Build()
            .AddEnvironment("UAT")
                .AddPermission(_userOId, "Test User 1", SystemPermissionRoleType.Writer)
                .AddPermission(_otherUserOId, "Test User 2", SystemPermissionRoleType.Writer)
                .Build()
            .AddEnvironment("Production")
                .AddPermission(_userOId, "Test User 1", SystemPermissionRoleType.Writer)
                .AddPermission(_otherUserOId, "Test User 2", SystemPermissionRoleType.Writer)
                .Build()
            .Build();
        var role = systemPermission.Environments[2].Permissions[1];  // removing _otherUser from Production
        var roleEnvironment = systemPermission.Environments[1];

        _mockConfirmationService.ConfirmAsync(
            SystemOwnerService.UserSystemPermissionEnvironmentAccessRemovalConfirmation.Title,
            Arg.Any<string>())
            .Returns(true);

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            await _mockConfirmationService.Received(1).ConfirmAsync(
                SystemOwnerService.UserSystemPermissionEnvironmentAccessRemovalConfirmation.Title,
                SystemOwnerService.UserSystemPermissionEnvironmentAccessRemovalConfirmation.FormatMessage(role, roleEnvironment.Environment));
        }
    }

    #endregion

    #region CheckUserAssignmentRemovalConditions - Reader Role Deletion

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfMoreThanOneReader_RequestsDeletionConfirmation()
    {
        // Arrange
        var systemPermission = new SystemPermissionDtoReadBuilder()
            .AddEnvironment("Development")
                .AddPermission(_userOId, "Test User 1", SystemPermissionRoleType.Reader)
                .Build()
            .AddEnvironment("Production")
                .AddPermission(_userOId, "Test User 1", SystemPermissionRoleType.Reader)
                .Build()
            .Build();
        var role = systemPermission.Environments[0].Permissions[0];
        var roleEnvironment = systemPermission.Environments[0];

        _mockConfirmationService.ConfirmAsync(
            SystemOwnerService.UserSystemPermissionEnvironmentAccessRemovalConfirmation.Title,
            Arg.Any<string>())
            .Returns(true);

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            await _mockConfirmationService.Received(1).ConfirmAsync(
                SystemOwnerService.UserSystemPermissionEnvironmentAccessRemovalConfirmation.Title,
                SystemOwnerService.UserSystemPermissionEnvironmentAccessRemovalConfirmation.FormatMessage(role, roleEnvironment.Environment));
        }
    }

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfLastReader_RequestsDeletionConfirmation()
    {
        // Arrange
        var systemPermission = CreateSystemPermissionWithReader(_userOId);
        var role = systemPermission.Environments[0].Permissions[0];
        var roleEnvironment = systemPermission.Environments[0];

        _mockConfirmationService.ConfirmAsync(
            SystemOwnerService.UserSystemPermissionAccessRemovalConfirmation.Title,
            Arg.Any<string>())
            .Returns(true);

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            await _mockConfirmationService.Received(1).ConfirmAsync(
                SystemOwnerService.UserSystemPermissionAccessRemovalConfirmation.Title,
                SystemOwnerService.UserSystemPermissionAccessRemovalConfirmation.FormatMessage(role, systemPermission.Name));
        }
    }

    [Test]
    public async Task CheckUserAssignmentRemovalConditions_IfReader_WhenUserDeclinesConfirmation_ReturnsFalse()
    {
        // Arrange
        var systemPermission = CreateSystemPermissionWithReader(_userOId);
        var role = systemPermission.Environments[0].Permissions[0];
        var roleEnvironment = systemPermission.Environments[0];

        _mockConfirmationService.ConfirmAsync(
            SystemOwnerService.UserSystemPermissionAccessRemovalConfirmation.Title,
            Arg.Any<string>())
            .Returns(false);

        // Act
        var result = await _sut.CheckUserAssignmentRemovalConditions(
            systemPermission, roleEnvironment, role);

        // Assert
        Assert.That(result, Is.False);
    }

    #endregion

    #region Helper Methods

    private static SystemPermissionDtoRead CreateSystemPermissionWithFullWriter(string userOId)
    {
        return new SystemPermissionDtoReadBuilder()
            .AddEnvironment("Development")
                .AddPermission(userOId, "Test User", SystemPermissionRoleType.Writer)
                .Build()
            .AddEnvironment("Production")
                .AddPermission(userOId, "Test User", SystemPermissionRoleType.Writer)
                .Build()
            .Build();
    }

    private static SystemPermissionDtoRead CreateSystemPermissionWithTwoFullWriters(string userOId1, string userOId2)
    {
        return new SystemPermissionDtoReadBuilder()
            .AddEnvironment("Development")
                .AddPermission(userOId1, "Test User 1", SystemPermissionRoleType.Writer)
                .AddPermission(userOId2, "Test User 2", SystemPermissionRoleType.Writer)
                .Build()
            .AddEnvironment("Production")
                .AddPermission(userOId1, "Test User 1", SystemPermissionRoleType.Writer)
                .AddPermission(userOId2, "Test User 2", SystemPermissionRoleType.Writer)
                .Build()
            .Build();
    }

    private static SystemPermissionDtoRead CreateSystemPermissionWithReader(string userOId)
    {
        return new SystemPermissionDtoReadBuilder()
            .AddEnvironment("Development")
                .AddPermission(userOId, "Test User 1", SystemPermissionRoleType.Reader)
                .Build()
            .Build();
    }

    private static SystemPermissionDtoRead CreateSystemPermissionWithSingleWriterInEachEnvironment(string userOId1, string userOId2)
    {
        return new SystemPermissionDtoReadBuilder()
            .AddEnvironment("Development")
                .AddPermission(userOId1, "Test User 1", SystemPermissionRoleType.Writer)
                .Build()
            .AddEnvironment("Production")
                .AddPermission(userOId2, "Test User 2", SystemPermissionRoleType.Writer)
                .Build()
            .Build();
    }

    #endregion
}
