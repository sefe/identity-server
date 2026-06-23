// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Data.Services;

namespace IdentityServer.Data.Test.Services;

[TestFixture]
public class ReportingServiceTests
{
    private const string _role1Name = "TestRole1";
    private const string _role2Name = "TestRole2";

    private IStorage<ApiResourceExt> _apiStorage;
    private ReportingService _service;
    private readonly ApiResourceExt _testResource = GetTestResource();

    [SetUp]
    public void SetUp()
    {
        _apiStorage = Substitute.For<IStorage<ApiResourceExt>>();
        _service = new ReportingService(_apiStorage);
    }

    private static ApiResourceExt GetTestResource()
    {
        var api = new ApiResourceExt
        {
            Name = "testapi",
            SystemPermissionEnvironment = new SystemPermissionEnvironment
            {
                Id = 1,
                Environment = SystemPermissionEnvironmentNames.Development,
                SystemPermission = new SystemPermission
                {
                    Id = 1,
                    Name = "TestPermission",
                    Description = "Test permission for API",
                    Created = DateTime.UtcNow,
                },
                SystemPermissionId = 1,
                Permissions = new List<SystemPermissionRole>
                {
                    new() {
                        Id = 1,
                        Name = _role1Name,
                        RoleType = SystemPermissionRoleType.Writer,
                        OId = Guid.NewGuid().ToString(),
                    }
                }
            },
            Roles = new List<ApiResourceRole>
            {
                new() {
                    RoleName = _role1Name,
                    Mappings = new List<RoleMapping>
                    {
                        new() {
                            MappingType = RoleMapType.UserObjectId,
                            Value = "123",
                            Description = "User1"
                        },
                        new() {
                            MappingType = RoleMapType.UserObjectId,
                            Value = "456",
                            Description = "User2"
                        },
                        new() {
                            MappingType = RoleMapType.UserObjectId,
                            Value = "789",
                            Description = "User9"
                        },
                        new() {
                            MappingType = RoleMapType.SecurityGroup,
                            Value = "123-group1",
                            Description = "group1"
                        },
                        new() {
                            MappingType = RoleMapType.ClientId,
                            Value = "456-client1",
                            Description = "client1"
                        },
                    }
                },
                new() {
                    RoleName = _role2Name,
                    Mappings = new List<RoleMapping>
                    {
                        new() {
                            MappingType = RoleMapType.UserObjectId,
                            Value = "1234",
                            Description = "User1"
                        },
                        new() {
                            MappingType = RoleMapType.UserObjectId,
                            Value = "4567",
                            Description = "User2"
                        },
                        new() {
                            MappingType = RoleMapType.UserObjectId,
                            Value = "7890",
                            Description = "User9"
                        },
                        new() {
                            MappingType = RoleMapType.SecurityGroup,
                            Value = "123-group2",
                            Description = "group2"
                        },
                        new() {
                            MappingType = RoleMapType.ClientId,
                            Value = "456-client2",
                            Description = "client2"
                        },
                    }
                }
            }
        };
        return api;
    }

    [Test]
    public void BuildReportAsync_ApiResourceNotFound_ThrowsEntityReferenceException()
    {
        // Arrange
        var request = new ApiRolesReportRequest { ApiResourceName = "TestApi" };
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>()).Returns((ApiResourceExt)null);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityReferenceException>(() => _service.BuildReportAsync(request));
        Assert.That(ex.Message, Does.Contain("API resource with name"));
    }

    [Test]
    public void BuildReportAsync_RoleNotFound_ThrowsEntityReferenceException()
    {
        // Arrange
        var request = new ApiRolesReportRequest { ApiResourceName = "TestApi", Role = "non-existent" };
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>()).Returns(_testResource);

        // Act & Assert
        var ex = Assert.ThrowsAsync<EntityReferenceException>(() => _service.BuildReportAsync(request));
        Assert.That(ex.Message, Does.Contain("No roles found for API resource"));
    }

    [Test]
    public async Task BuildReportAsync_ValidRequest_ReturnsAssignments()
    {
        // Arrange
        var request = new ApiRolesReportRequest { ApiResourceName = "TestApi" };
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>()).Returns(_testResource);

        // Act
        var result = await _service.BuildReportAsync(request);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.ApiResourceName, Is.EqualTo("testapi"));
            Assert.That(result.Assignments.ContainsKey(_role1Name), Is.True);
            Assert.That(result.Assignments[_role1Name], Has.Count.EqualTo(5));
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.UserObjectId && _.Id == "123"), Is.True);
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.UserObjectId && _.Id == "456"), Is.True);
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.UserObjectId && _.Id == "789"), Is.True);
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.SecurityGroup && _.Id == "123-group1"), Is.True);
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.ClientId && _.Id == "456-client1"), Is.True);
            Assert.That(result.Assignments.ContainsKey(_role2Name), Is.True);
            Assert.That(result.Assignments[_role2Name], Has.Count.EqualTo(5));
            Assert.That(result.Assignments[_role2Name].Any(_ => _.Type == RoleMapType.UserObjectId && _.Id == "1234"), Is.True);
            Assert.That(result.Assignments[_role2Name].Any(_ => _.Type == RoleMapType.UserObjectId && _.Id == "4567"), Is.True);
            Assert.That(result.Assignments[_role2Name].Any(_ => _.Type == RoleMapType.UserObjectId && _.Id == "7890"), Is.True);
            Assert.That(result.Assignments[_role2Name].Any(_ => _.Type == RoleMapType.SecurityGroup && _.Id == "123-group2"), Is.True);
            Assert.That(result.Assignments[_role2Name].Any(_ => _.Type == RoleMapType.ClientId && _.Id == "456-client2"), Is.True);
        }
    }

    [Test]
    public async Task BuildReportAsync_WithRoleMapType_FiltersMappings()
    {
        // Arrange
        var request = new ApiRolesReportRequest { ApiResourceName = "TestApi", RoleMapType = RoleMapType.ClientId.ToString() };
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>()).Returns(_testResource);

        // Act
        var result = await _service.BuildReportAsync(request);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Assignments, Has.Count.EqualTo(2));
            Assert.That(result.Assignments[_role1Name], Has.Count.EqualTo(1));
            Assert.That(result.Assignments[_role1Name][0].Id, Is.EqualTo("456-client1"));
            Assert.That(result.Assignments[_role2Name], Has.Count.EqualTo(1));
            Assert.That(result.Assignments[_role2Name][0].Id, Is.EqualTo("456-client2"));
        }
    }

    [Test]
    public async Task BuildReportAsync_WithRole_FiltersRoles()
    {
        // Arrange
        var request = new ApiRolesReportRequest { ApiResourceName = "TestApi", Role = _role1Name };
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>()).Returns(_testResource);

        // Act
        var result = await _service.BuildReportAsync(request);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Assignments, Has.Count.EqualTo(1));
            Assert.That(result.Assignments[_role1Name], Has.Count.EqualTo(5));
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.UserObjectId && _.Id == "123"), Is.True);
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.UserObjectId && _.Id == "456"), Is.True);
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.UserObjectId && _.Id == "789"), Is.True);
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.SecurityGroup && _.Id == "123-group1"), Is.True);
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.ClientId && _.Id == "456-client1"), Is.True);
        }
    }

    [Test]
    public async Task BuildReportAsync_WithRoleAndMapType_FiltersRolesAndMapTypes()
    {
        // Arrange
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>()).Returns(_testResource);

        // Act
        var request = new ApiRolesReportRequest { ApiResourceName = "TestApi", Role = _role1Name, RoleMapType = RoleMapType.ClientId.ToString() };
        var result = await _service.BuildReportAsync(request);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Assignments, Has.Count.EqualTo(1));
            Assert.That(result.Assignments[_role1Name], Has.Count.EqualTo(1));
            Assert.That(result.Assignments[_role1Name].Any(_ => _.Type == RoleMapType.ClientId && _.Id == "456-client1"), Is.True);
        }
    }
}
