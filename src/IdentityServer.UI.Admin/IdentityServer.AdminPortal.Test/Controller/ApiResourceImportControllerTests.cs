using Microsoft.AspNetCore.Mvc;
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
public class ApiResourceImportControllerTests : ControllerTestBase
{
    private ApiResourceImportController _importController;
    private ApiResourceController _apiResourceController;
    private IRoleMappingValidationService _roleMappingValidationService;
    private IStorage<ApiResourceExt> _apiResourceStorage;

    [SetUp]
    public async Task Setup()
    {
        _roleMappingValidationService = Substitute.For<IRoleMappingValidationService>();
        _roleMappingValidationService.ValidateApiRoleMappingAsync(Arg.Any<Data.Entities.Roles.RoleMapping>()).Returns(new OperationStatus { IsCompleted = true });

        var provider = IoC.GetProvider(sc =>
        {
            sc.AddScoped<ApiResourceImportController>();
            sc.AddScoped<ApiResourceController>();
            sc.ReplaceWithInstance(EverythingIsAllowed);
            sc.ReplaceWithInstance(_roleMappingValidationService);
        });

        await Setup(provider);

        _importController = provider.GetRequiredService<ApiResourceImportController>();
        _apiResourceController = provider.GetRequiredService<ApiResourceController>();
        _apiResourceStorage = provider.GetRequiredService<IStorage<ApiResourceExt>>();
    }

    [Test]
    public void ImportApiResourceRoles_WithInvalidApiId_Fails()
    {
        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _importController.ImportApiResourceRoles(9999, new ApiResourceRoleImportDto { Roles = [] }));
    }

    [Test]
    public async Task ImportApiResourceRoles_WithFailingValidationCheck_ThrowsImportValidationException()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var importDto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new()
            {
                new() { RoleName = "DuplicateRole", Mappings = new() { new() { MappingType = "Direct", Value = "A" } } },
                new() { RoleName = "DuplicateRole", Mappings = new() { new() { MappingType = "Direct", Value = "B" } } }
            }
        };
        SetControllerContext(_importController, Admin);

        // Act & Assert
        using (Assert.EnterMultipleScope())
        {
            var ex = Assert.ThrowsAsync<ImportValidationException>(() => _importController.ImportApiResourceRoles(api.Id, importDto));
            Assert.That(ex!.ValidationSummary.Errors, Has.Some.Contains("Duplicate role names"));
            await _roleMappingValidationService.Received(1).ValidateImportRoleMappingsAsync(Arg.Any<List<RoleMappingValueObject>>(), Arg.Any<OperationStatus>());
        }
    }

    [Test]
    public async Task ImportApiResourceRoles_WithInvalidImportStrategy_ThrowsException()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var importDto = new ApiResourceRoleImportDto
        {
            ImportStrategy = (ImportStrategy)999,
            Roles = new()
            {
                new() { RoleName = "Role", Mappings = new() { new() { MappingType = "UserObjectId", Value = "A" } } },
            }
        };
        SetControllerContext(_importController, Admin);

        // Act & Assert
        var ex = Assert.ThrowsAsync<ImportValidationException>(() => _importController.ImportApiResourceRoles(api.Id, importDto));
        Assert.That(ex, Is.Not.Null);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(ex!.Message, Does.Contain("Unknown import strategy for API Resource roles."));
            Assert.That(ex.ValidationSummary.Errors, Has.Count.EqualTo(0));
            Assert.That(ex.ValidationSummary.Warnings, Has.Count.EqualTo(0));
        }
    }

    [Test]
    public async Task ImportApiResourceRoles_AddStrategy_WithValidMappings_AddsMappings()
    {
        // Arrange
        var existingRoleName = "ExistingRole";
        var newRoleName = "NewRole";
        var apiBuilder = new ApiResourceExtBuilder("api1");
        apiBuilder.WithRole(existingRoleName, new List<Data.Entities.Roles.RoleMapping>()
        {
            new() { Value = "ExistingUserId", MappingType = RoleMapType.UserObjectId },
            new() { Value = "ExistingUserId2", MappingType = RoleMapType.UserObjectId }
        });
        var api = apiBuilder.Build();
        api = await _apiResourceStorage.AddAsync(api);

        var importDto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new()
            {
                new() { RoleName = newRoleName, Mappings = new() {
                    new() { MappingType = "UserObjectId", Value = "NewUserId1" },
                    new() { MappingType = "SecurityGroup", Value = "NewSecurityGroup1" },
                    new() { MappingType = "ClientId", Value = "NewClientId1" }} },
                new() { RoleName = existingRoleName, Mappings = new() {
                    new() { MappingType = "UserObjectId", Value = "NewUserId1" },
                    new() { MappingType = "UserObjectId", Value = "existinguserid2" }, //mind the case difference
                } },
            }
        };

        SetControllerContext(_importController, Admin);

        // Act
        await _importController.ImportApiResourceRoles(api.Id, importDto);

        // Assert
        var updatedApi = await _apiResourceController.Call_GetApiResourceAsync(api.Id, Admin);
        Assert.That(updatedApi.Roles, Has.Count.EqualTo(2));

        var updatedExistingRole = updatedApi.Roles.First(r => r.RoleName == existingRoleName);
        Assert.That(updatedExistingRole.Mappings, Has.Count.EqualTo(3));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == RoleMapType.UserObjectId && m.Value == "ExistingUserId"), Is.True);
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == RoleMapType.UserObjectId && m.Value == "ExistingUserId2"), Is.True); //case insensitive match, should not add duplicate
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == RoleMapType.UserObjectId && m.Value == "NewUserId1"), Is.True);
        }

        var updatedNewRole = updatedApi.Roles.First(r => r.RoleName == newRoleName);
        Assert.That(updatedNewRole.Mappings, Has.Count.EqualTo(3));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == RoleMapType.UserObjectId && m.Value == "NewUserId1"), Is.True);
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == RoleMapType.SecurityGroup && m.Value == "NewSecurityGroup1"), Is.True);
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == RoleMapType.ClientId && m.Value == "NewClientId1"), Is.True);
        }
    }

    [Test]
    public async Task ImportApiResourceRoles_ReplaceStrategy_WithValidMappings_ReplacesMappings()
    {
        // Arrange
        var existingRoleName = "ExistingRole";
        var newRoleName = "NewRole";
        var obsoleteRoleName = "OldRole";
        var apiBuilder = new ApiResourceExtBuilder("api1");
        apiBuilder.WithRole(existingRoleName, new List<Data.Entities.Roles.RoleMapping>()
        {
            new() { Value = "ExistingUserId", MappingType = RoleMapType.UserObjectId },
            new() { Value = "ExistingUserId2", MappingType = RoleMapType.UserObjectId }
        });
        apiBuilder.WithRole(obsoleteRoleName, new List<Data.Entities.Roles.RoleMapping>()
        {
            new() { Value = "ObsoleteUserId", MappingType = RoleMapType.UserObjectId },
        });
        var api = apiBuilder.Build();
        api = await _apiResourceStorage.AddAsync(api);

        var importDto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Replace,
            Roles = new()
            {
                new() { RoleName = newRoleName, Mappings = new() {
                    new() { MappingType = "UserObjectId", Value = "NewUserId1" },
                    new() { MappingType = "SecurityGroup", Value = "NewSecurityGroup1" },
                    new() { MappingType = "ClientId", Value = "NewClientId1" }} },
                new() { RoleName = existingRoleName, Mappings = new() {
                    new() { MappingType = "UserObjectId", Value = "NewUserId1" },
                    new() { MappingType = "UserObjectId", Value = "existinguserid2" }, //mind the case difference
                } },
            }
        };

        SetControllerContext(_importController, Admin);

        // Act
        await _importController.ImportApiResourceRoles(api.Id, importDto);

        // Assert
        var updatedApi = await _apiResourceController.Call_GetApiResourceAsync(api.Id, Admin);
        Assert.That(updatedApi.Roles, Has.Count.EqualTo(2));

        var updatedExistingRole = updatedApi.Roles.First(r => r.RoleName == existingRoleName);
        Assert.That(updatedExistingRole.Mappings, Has.Count.EqualTo(2));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == RoleMapType.UserObjectId && m.Value == "existinguserid2"), Is.True);
            Assert.That(updatedExistingRole.Mappings.Any(m => m.MappingType == RoleMapType.UserObjectId && m.Value == "NewUserId1"), Is.True);
        }

        var updatedNewRole = updatedApi.Roles.First(r => r.RoleName == newRoleName);
        Assert.That(updatedNewRole.Mappings, Has.Count.EqualTo(3));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == RoleMapType.UserObjectId && m.Value == "NewUserId1"), Is.True);
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == RoleMapType.SecurityGroup && m.Value == "NewSecurityGroup1"), Is.True);
            Assert.That(updatedNewRole.Mappings.Any(m => m.MappingType == RoleMapType.ClientId && m.Value == "NewClientId1"), Is.True);
        }
    }

    [Test]
    public void ValidateImportApiResourceRoles_WithInvalidApiId_Fails()
    {
        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(() => _importController.ValidateImportApiResourceRoles(9999, new ApiResourceRoleImportDto { Roles = [] }));
    }

    [Test]
    public async Task ValidateImportApiResourceRoles_WithFailingValidationCheck_ReturnsErrors()
    {
        // Arrange
        var api = await _apiResourceController.Call_CreateApiResourceAsync(ApiResourceControllerExtensions.GetDefaultApiResource(1), Admin);
        var importDto = new ApiResourceRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new()
            {
                new() { RoleName = "DuplicateRole", Mappings = new() { new() { MappingType = "Direct", Value = "A" } } },
                new() { RoleName = "DuplicateRole", Mappings = new() { new() { MappingType = "Direct", Value = "B" } } }
            }
        };
        SetControllerContext(_importController, Admin);

        // Act
        var result = await _importController.ValidateImportApiResourceRoles(api.Id, importDto);
        var status = (result.Result as OkObjectResult)?.Value as OperationStatus;
        using (Assert.EnterMultipleScope())
        {
            Assert.That(status, Is.Not.Null);
            Assert.That(status!.Errors, Has.Some.Contains("Duplicate role names"));
        }
        await _roleMappingValidationService.Received(1).ValidateImportRoleMappingsAsync(Arg.Any<List<RoleMappingValueObject>>(), Arg.Any<OperationStatus>());
    }
}
