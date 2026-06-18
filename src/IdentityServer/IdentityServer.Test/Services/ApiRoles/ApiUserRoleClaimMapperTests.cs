using System.Linq.Expressions;
using System.Security.Claims;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Services.ApiRoles;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Test.Services.ApiRoles;

[TestFixture]
public class ApiUserRoleClaimMapperTests
{
    private IStorage<ApiResourceExt> _apiStorage;
    private IEntraUserService _entraService;
    private ApiUserRoleClaimMapper _sut;
    private Microsoft.Extensions.Logging.ILogger<ApiUserRoleClaimMapper> _logger;

    [SetUp]
    public void SetUp()
    {
        _apiStorage = Substitute.For<IStorage<ApiResourceExt>>();
        _entraService = Substitute.For<IEntraUserService>();
        _logger = Substitute.For<Microsoft.Extensions.Logging.ILogger<ApiUserRoleClaimMapper>>();
        _sut = new ApiUserRoleClaimMapper(_apiStorage, _entraService, _logger);
    }

    [Test]
    public async Task ProcessApiRoleMappingsForUserAsync_MultipleApiNames_YieldsClaimsFromAll()
    {
        // Arrange
        var apiNames = new[] { "api1", "api2" };
        var userId = "user1";

        // Each API resource has a role with a valid SecurityGroup mapping
        var apiResource1 = new ApiResourceExtBuilder("api1").WithRole("role1", new List<RoleMapping>
        {
            new()
            {
                MappingType = RoleMapType.SecurityGroup,
                Value = "group1"
            }
        }).Build();
        var apiResource2 = new ApiResourceExtBuilder("api2").WithRole("role2", new List<RoleMapping>
        {
            new()
            {
                MappingType = RoleMapType.SecurityGroup,
                Value = "group2"
            }
        }).Build();

        // Return the correct resource for each API name
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns(callInfo =>
            {
                var predicate = callInfo.Arg<Expression<Func<ApiResourceExt, bool>>>();
                var compiled = predicate.Compile();
                if (compiled(apiResource1))
                {
                    return apiResource1;
                }

                if (compiled(apiResource2))
                {
                    return apiResource2;
                }

                return null;
            });

        // Mock user group membership to include both groups
        _entraService.GetUserMembershipInGroups(userId, Arg.Any<IEnumerable<string>>())
            .Returns(Task.FromResult(new List<Group>
            {
                new() { Id = "group1" },
                new() { Id = "group2" }
            }));

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _sut.ProcessApiRoleMappingsForUserAsync(apiNames, userId))
        {
            result.Add(claim);
        }

        // Assert
        Assert.That(result, Is.Not.Empty);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Any(c => c.Type == Abstraction.Constants.ClaimNames.UserRole && c.Value == "role1"), Is.True);
            Assert.That(result.Any(c => c.Type == Abstraction.Constants.ClaimNames.UserRole && c.Value == "role2"), Is.True);
        }
    }

    [Test]
    public async Task MapUserGroupsToApiRolesAsync_ApiResourceNotFound_YieldsNoClaims()
    {
        // Arrange
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns((ApiResourceExt)null);
        var userId = "user1";

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _sut.MapUserGroupsToApiRolesAsync("api1", userId))
        {
            result.Add(claim);
        }

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public async Task MapUserGroupsToApiRolesAsync_NoRoles_YieldsNoClaims()
    {
        // Arrange
        var apiResource = new ApiResourceExtBuilder("api1").Build();
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns(apiResource);

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _sut.MapUserGroupsToApiRolesAsync("api1", "user1"))
        {
            result.Add(claim);
        }

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public async Task MapUserGroupsToApiRolesAsync_RolesWithNoMappings_YieldsNoClaims()
    {
        // Arrange
        var apiResource = new ApiResourceExtBuilder("api1").WithRole("role1", new List<RoleMapping>()).Build();
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns(apiResource);

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _sut.MapUserGroupsToApiRolesAsync("api1", "user1"))
        {
            result.Add(claim);
        }

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public async Task MapUserGroupsToApiRolesAsync_IgnoreUnsupportedMappingTypes()
    {
        // Arrange
        var apiName = "api";

        var apiResource1 = new ApiResourceExtBuilder(apiName)
            .WithRole("role", new List<RoleMapping>
                {
                    new() {
                        MappingType = RoleMapType.ClientId,
                        Value = "ClientName"
                    }
                }
            )
            .Build();

        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns(callInfo => apiResource1);

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _sut.MapUserGroupsToApiRolesAsync(apiName, "user1"))
        {
            result.Add(claim);
        }

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Empty);
            Assert.That(_logger.ReceivedCalls(), Is.Empty);
        }
    }

    [Test]
    public async Task MapUserGroupsToApiRolesAsync_ValidMapping_YieldsClaim()
    {
        // Arrange
        var mapping = new RoleMapping
        {
            MappingType = RoleMapType.SecurityGroup,
            Value = "group1"
        };

        var apiResource = new ApiResourceExtBuilder("api1").WithRole("role1", new List<RoleMapping> { mapping }).Build();
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns(apiResource);

        _entraService.GetUserMembershipInGroups("user1", Arg.Any<IEnumerable<string>>())
            .Returns(Task.FromResult(new List<Group> { new() { Id = "group1" } }));

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _sut.MapUserGroupsToApiRolesAsync("api1", "user1"))
        {
            result.Add(claim);
        }

        // Assert
        Assert.That(result, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result[0].Type, Is.EqualTo(Abstraction.Constants.ClaimNames.UserRole));
            Assert.That(result[0].Value, Is.EqualTo("role1"));
        }
    }

    [Test]
    public async Task GetUserMembershipInMappedGroupsAsync_WithGroups_ReturnsHashSet()
    {
        // Arrange
        var groupIds = new List<string> { "g1", "g2" };
        _entraService.GetUserMembershipInGroups("user1", groupIds)
            .Returns(Task.FromResult(new List<Group>
            {
                new() { Id = "g1" },
                new() { Id = "g2" }
            }));
        string[] expected = new[] { "g1", "g2" };

        // Act
        var result = await _sut.GetUserMembershipInMappedGroupsAsync("user1", groupIds);

        // Assert
        Assert.That(result, Is.EquivalentTo(expected));
    }

    [Test]
    public async Task GetUserMembershipInMappedGroupsAsync_EmptyGroups_ReturnsEmptyHashSet()
    {
        // Act
        var result = await _sut.GetUserMembershipInMappedGroupsAsync("user1", new List<string>());

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public void GetSecurityGroupIdsFromRoleMappings_ReturnsOnlySecurityGroupIds()
    {
        // Arrange
        var apiResource = new ApiResourceExtBuilder("api1")
            .WithRole("role1", new List<RoleMapping>
                {
                    new() { MappingType = RoleMapType.SecurityGroup, Value = "g1" },
                    new() { MappingType = RoleMapType.UserObjectId, Value = "u1" },
                    new() { MappingType = RoleMapType.SecurityGroup, Value = "g2" }
                }).Build();
        string[] expected = new[] { "g1", "g2" };

        // Act
        var result = ApiUserRoleClaimMapper.GetSecurityGroupIdsFromRoleMappings(apiResource);

        // Assert
        Assert.That(result, Is.EquivalentTo(expected));
    }

    [Test]
    public void MapApiRolesToClaims_NullOrEmptyRoles_YieldsNoClaims()
    {
        // Act
        var result1 = _sut.MapApiRolesToClaims(null, "api", "user", new HashSet<string>());
        var result2 = _sut.MapApiRolesToClaims(new List<ApiResourceRole>(), "api", "user", new HashSet<string>());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result1, Is.Empty);
            Assert.That(result2, Is.Empty);
        }
    }

    [Test]
    public void MapApiRolesToClaims_ValidRoleWithClaim_YieldsClaim()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.UserObjectId, Value = "user1" };
        var role = new ApiResourceRole { RoleName = "role1", Mappings = new List<RoleMapping> { mapping } };
        var roles = new List<ApiResourceRole> { role };

        // Act
        var result = _sut.MapApiRolesToClaims(roles, "api", "user1", new HashSet<string>());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Count(), Is.EqualTo(1));
            Assert.That(result.First().Type, Is.EqualTo(Abstraction.Constants.ClaimNames.UserRole));
            Assert.That(result.First().Value, Is.EqualTo("role1"));
        }
    }

    [Test]
    public void ProcessCustomRole_NoMappings_YieldsNoClaims()
    {
        // Arrange
        var role = new ApiResourceRole { RoleName = "role1", Mappings = new List<RoleMapping>() };

        // Act
        var result = _sut.ProcessCustomRole("api", role, "user", new HashSet<string>());

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public void ProcessCustomRole_ValidMappingAndMatch_YieldsClaim()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.UserObjectId, Value = "user1" };
        var role = new ApiResourceRole { RoleName = "role1", Mappings = new List<RoleMapping> { mapping } };

        // Act
        var result = _sut.ProcessCustomRole("api", role, "user1", new HashSet<string>());

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result.Count(), Is.EqualTo(1));
            Assert.That(result.First().Type, Is.EqualTo(Abstraction.Constants.ClaimNames.UserRole));
            Assert.That(result.First().Value, Is.EqualTo("role1"));
        }
    }

    [Test]
    public void IsValidRoleMapping_NullMapping_ReturnsFalse()
    {
        // Act
        var result = _sut.IsValidRoleMapping("api", "role", null);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void IsValidRoleMapping_EmptyValue_ReturnsFalse()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.SecurityGroup, Value = "" };

        // Act
        var result = _sut.IsValidRoleMapping("api", "role", mapping);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void IsValidRoleMapping_ValidMapping_ReturnsTrue()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.SecurityGroup, Value = "g1" };

        // Act
        var result = _sut.IsValidRoleMapping("api", "role", mapping);

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void HasMappingMatch_SecurityGroupType_ReturnsTrueIfInUserGroups()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.SecurityGroup, Value = "g1" };
        var userGroups = new HashSet<string> { "g1" };

        // Act
        var result = ApiUserRoleClaimMapper.HasMappingMatch(mapping, "user", userGroups);

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void HasMappingMatch_UserObjectIdType_ReturnsTrueIfUserIdMatches()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.UserObjectId, Value = "user1" };

        // Act
        var result = ApiUserRoleClaimMapper.HasMappingMatch(mapping, "user1", new HashSet<string>());

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void HasMappingMatch_UnsupportedType_ReturnsFalse()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = (RoleMapType)99, Value = "x" };

        // Act
        var result = ApiUserRoleClaimMapper.HasMappingMatch(mapping, "user", new HashSet<string>());

        // Assert
        Assert.That(result, Is.False);
    }
}
