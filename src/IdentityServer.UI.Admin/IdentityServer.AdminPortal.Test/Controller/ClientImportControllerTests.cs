// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.AdminPortal.Server.Controllers;
using IdentityServer.AdminPortal.Test.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Services;
using IdentityServer.Tests.Common;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.AdminPortal.Test.Controller;

[TestFixture]
public class ClientImportControllerTests : ControllerTestBase
{
    private ClientImportController _importController;
    private ClientController _clientController;
    private IRoleMappingValidationService _roleMappingValidationService;
    private IStorage<ClientExt> _clientStorage;

    [SetUp]
    public async Task Setup()
    {
        _roleMappingValidationService = Substitute.For<IRoleMappingValidationService>();
        _roleMappingValidationService.ValidateClientRoleMappingAsync(Arg.Any<Data.Entities.Roles.ClientRoleMapping>()).Returns(new OperationStatus { IsCompleted = true });

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ClientImportController>();
            sc.AddScoped<ClientController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_roleMappingValidationService);
        });

        await Setup(provider);

        _importController = provider.GetRequiredService<ClientImportController>();
        _clientController = provider.GetRequiredService<ClientController>();
        _clientStorage = provider.GetRequiredService<IStorage<ClientExt>>();
    }

    [Test]
    public void ImportClientRoles_WithInvalidClientId_Fails()
    {
        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _importController.Call_ImportClientRolesAsync(9999, new ClientRoleImportDto { Roles = [] }, Admin));
    }

    [Test]
    public async Task ImportClientRoles_WithFailingValidationCheck_ThrowsImportValidationException()
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var importDto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new()
            {
                new() { RoleName = "DuplicateRole", Mappings = new() { new() { MappingType = "Direct", Value = "A" } } },
                new() { RoleName = "DuplicateRole", Mappings = new() { new() { MappingType = "Direct", Value = "B" } } }
            }
        };

        // Act & Assert
        using (Assert.EnterMultipleScope())
        {
            var ex = Assert.ThrowsAsync<ImportValidationException>(() => _importController.Call_ImportClientRolesAsync(client.Id, importDto, Admin));
            Assert.That(ex!.ValidationSummary.Errors, Has.Some.Contains("Duplicate role names"));
            await _roleMappingValidationService.Received(1).ValidateImportRoleMappingsAsync(Arg.Any<List<RoleMappingValueObject>>(), Arg.Any<OperationStatus>());
        }
    }

    [Test]
    public async Task ImportClientRoles_WithInvalidImportStrategy_ThrowsException()
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var importDto = new ClientRoleImportDto
        {
            ImportStrategy = (ImportStrategy)999,
            Roles = new()
            {
                new() { RoleName = "Role", Mappings = new() { new() { MappingType = "UserObjectId", Value = "A" } } },
            }
        };

        // Act & Assert
        var ex = Assert.ThrowsAsync<ImportValidationException>(() => _importController.Call_ImportClientRolesAsync(client.Id, importDto, Admin));
        Assert.That(ex, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(ex!.Message, Does.Contain("Unknown import strategy for Client roles."));
            Assert.That(ex.ValidationSummary.Errors, Has.Count.EqualTo(0));
            Assert.That(ex.ValidationSummary.Warnings, Has.Count.EqualTo(0));
        }
    }

    [Test]
    public async Task ImportClientRoles_AddStrategy_WithValidMappings_AddsMappings()
    {
        // Arrange
        var existingRoleName = "ExistingRole";
        var newRoleName = "NewRole";
        var client = new ClientExtBuilder("client1", "Client 1")
            .WithRole(existingRoleName, new List<Data.Entities.Roles.ClientRoleMapping>()
            {
                new() { Value = "ExistingUserId", MappingType = ClientRoleMapType.UserObjectId },
                new() { Value = "ExistingUserId2", MappingType = ClientRoleMapType.UserObjectId }
            }).Build();
        client = await _clientStorage.AddAsync(client);

        var importDto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new()
            {
                new() { RoleName = newRoleName, Mappings = new() {
                    new() { MappingType = "UserObjectId", Value = "NewUserId1" },
                    new() { MappingType = "SecurityGroup", Value = "NewSecurityGroup1" } } },
                new() { RoleName = existingRoleName, Mappings = new() {
                    new() { MappingType = "UserObjectId", Value = "NewUserId1" },
                    new() { MappingType = "UserObjectId", Value = "existinguserid2" }, //mind the case difference
                } },
            }
        };

        // Act
        await _importController.Call_ImportClientRolesAsync(client.Id, importDto, Admin);

        // Assert
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Admin);
        Assert.That(updatedClient.Roles, Has.Count.EqualTo(2));

        var updatedExistingRole = updatedClient.Roles.First(r => r.RoleName == existingRoleName);
        Assert.That(updatedExistingRole.Mappings, Has.Count.EqualTo(3));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == ClientRoleMapType.UserObjectId && m.Value == "ExistingUserId"), Is.True);
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == ClientRoleMapType.UserObjectId && m.Value == "ExistingUserId2"), Is.True); //case insensitive match, should not add duplicate
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == ClientRoleMapType.UserObjectId && m.Value == "NewUserId1"), Is.True);
        }

        var updatedNewRole = updatedClient.Roles.First(r => r.RoleName == newRoleName);
        Assert.That(updatedNewRole.Mappings, Has.Count.EqualTo(2));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == ClientRoleMapType.UserObjectId && m.Value == "NewUserId1"), Is.True);
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == ClientRoleMapType.SecurityGroup && m.Value == "NewSecurityGroup1"), Is.True);
        }
    }

    [Test]
    public async Task ImportClientRoles_ReplaceStrategy_WithValidMappings_ReplacesMappings()
    {
        // Arrange
        var existingRoleName = "ExistingRole";
        var newRoleName = "NewRole";
        var obsoleteRoleName = "OldRole";
        var clientBuilder = new ClientExtBuilder("client1", "Client 1");
        clientBuilder.WithRole(existingRoleName, new List<Data.Entities.Roles.ClientRoleMapping>()
        {
            new() { Value = "ExistingUserId", MappingType = ClientRoleMapType.UserObjectId },
            new() { Value = "ExistingUserId2", MappingType = ClientRoleMapType.UserObjectId }
        });
        clientBuilder.WithRole(obsoleteRoleName, new List<Data.Entities.Roles.ClientRoleMapping>()
        {
            new() { Value = "ObsoleteUserId", MappingType = ClientRoleMapType.UserObjectId },
        });
        var client = clientBuilder.Build();
        client = await _clientStorage.AddAsync(client);

        var importDto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new()
            {
                new() { RoleName = newRoleName, Mappings = new() {
                    new() { MappingType = "UserObjectId", Value = "NewUserId1" },
                    new() { MappingType = "SecurityGroup", Value = "NewSecurityGroup1" } } },
                new() { RoleName = existingRoleName, Mappings = new() {
                    new() { MappingType = "UserObjectId", Value = "NewUserId1" },
                    new() { MappingType = "UserObjectId", Value = "existinguserid2" }, //mind the case difference
                } },
            }
        };

        // Act
        await _importController.Call_ImportClientRolesAsync(client.Id, importDto, Admin);

        // Assert
        var updatedClient = await _clientController.Call_GetClientAsync(client.Id, Admin);
        Assert.That(updatedClient.Roles, Has.Count.EqualTo(2));

        var updatedExistingRole = updatedClient.Roles.First(r => r.RoleName == existingRoleName);
        Assert.That(updatedExistingRole.Mappings, Has.Count.EqualTo(2));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == ClientRoleMapType.UserObjectId && m.Value == "existinguserid2"), Is.True);
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == ClientRoleMapType.UserObjectId && m.Value == "NewUserId1"), Is.True);
        }

        var updatedNewRole = updatedClient.Roles.First(r => r.RoleName == newRoleName);
        Assert.That(updatedNewRole.Mappings, Has.Count.EqualTo(2));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == ClientRoleMapType.UserObjectId && m.Value == "NewUserId1"), Is.True);
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == ClientRoleMapType.SecurityGroup && m.Value == "NewSecurityGroup1"), Is.True);
        }
    }

    [Test]
    public void ValidateImportClientRoles_WithInvalidClientId_Fails()
    {
        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _importController.Call_ValidateImportClientRolesAsync(9999, new ClientRoleImportDto { Roles = [] }, Admin));
    }

    [Test]
    public async Task ValidateImportClientRoles_WithFailingValidationCheck_ReturnsErrors()
    {
        // Arrange
        var client = await _clientController.Call_CreateClientAsync(ClientControllerExtensions.GetDefaultClient(1), Admin);
        var importDto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new()
            {
                new() { RoleName = "DuplicateRole", Mappings = new() { new() { MappingType = "Direct", Value = "A" } } },
                new() { RoleName = "DuplicateRole", Mappings = new() { new() { MappingType = "Direct", Value = "B" } } }
            }
        };

        // Act
        var status = await _importController.Call_ValidateImportClientRolesAsync(client.Id, importDto, Admin);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(status, Is.Not.Null);
            Assert.That(status!.Errors, Has.Some.Contains("Duplicate role names"));
        }
        await _roleMappingValidationService.Received(1).ValidateImportRoleMappingsAsync(Arg.Any<List<RoleMappingValueObject>>(), Arg.Any<OperationStatus>());
    }
}
