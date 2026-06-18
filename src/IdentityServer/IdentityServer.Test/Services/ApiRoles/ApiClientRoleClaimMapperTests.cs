using System.Linq.Expressions;
using System.Security.Claims;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Services.ApiRoles;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Test.Services.ApiRoles;

[TestFixture]
public class ApiClientRoleClaimMapperTests
{
    private IStorage<ApiResourceExt> _apiStorage;
    private ApiClientRoleClaimMapper _mapper;
    private Microsoft.Extensions.Logging.ILogger<ApiClientRoleClaimMapper> _logger;

    [SetUp]
    public void SetUp()
    {
        _apiStorage = Substitute.For<IStorage<ApiResourceExt>>();
        _logger = Substitute.For<Microsoft.Extensions.Logging.ILogger<ApiClientRoleClaimMapper>>();
        _mapper = new ApiClientRoleClaimMapper(_apiStorage, _logger);
    }

    [Test]
    public async Task ProcessApiRoleMappingsForClientIdAsync_ReturnsClaims_ForMultipleApiResources()
    {
        // Arrange
        var apiNames = new[] { "api1", "api2" };
        var clientId = "client1";

        var apiResource1 = new ApiResourceExtBuilder("api1").WithRole("role1", new List<RoleMapping>
        {
            new() {
                MappingType = RoleMapType.ClientId,
                Value = clientId
            }
        }).Build();
        var apiResource2 = new ApiResourceExtBuilder("api2").WithRole("role2", new List<RoleMapping>
        {
            new() {
                MappingType = RoleMapType.ClientId,
                Value = clientId
            }
        }).Build();
        var apiResource3 = new ApiResourceExtBuilder("api3").WithRole("role3", new List<RoleMapping>
        {
            new() {
                MappingType = RoleMapType.ClientId,
                Value = clientId
            },
            new() {
                MappingType = RoleMapType.SecurityGroup,
                Value = "GroupId"
            },
            new() {
                MappingType = RoleMapType.UserObjectId,
                Value = "UserId"
            },
        }).Build();

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

                if (compiled(apiResource3))
                {
                    return apiResource3;
                }

                return null;
            });

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _mapper.ProcessApiRoleMappingsForClientIdAsync(apiNames, clientId))
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
    public async Task MapApiRolesToClaimsAsync_ReturnsNoClaims_WhenApiResourceNotFound()
    {
        // Arrange
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns((ApiResourceExt)null);

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _mapper.MapApiRolesToClaimsAsync("notfound", "client"))
        {
            result.Add(claim);
        }

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public async Task MapApiRolesToClaimsAsync_ReturnsNoClaims_WhenNoRoles()
    {
        // Arrange
        var api = new ApiResourceExtBuilder("api").Build();
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns(api);

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _mapper.MapApiRolesToClaimsAsync("api", "client"))
        {
            result.Add(claim);
        }

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public async Task MapApiRolesToClaimsAsync_ReturnsNoClaims_WhenRolesHaveNoMappings()
    {
        // Arrange
        var api = new ApiResourceExtBuilder("api").WithRole("role1", new List<RoleMapping>()).Build();
        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns(api);

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _mapper.MapApiRolesToClaimsAsync("api", "client"))
        {
            result.Add(claim);
        }

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public async Task MapApiRolesToClaimsAsync_IgnoreUnsupportedMappingTypes()
    {
        // Arrange
        var apiName = "api";
        var clientId = "client";

        var apiResource1 = new ApiResourceExtBuilder(apiName)
            .WithRole("role", new List<RoleMapping>
                {
                    new() {
                        MappingType = RoleMapType.SecurityGroup,
                        Value = "GroupId"
                    },
                    new() {
                        MappingType = RoleMapType.UserObjectId,
                        Value = "UserId"
                    }
                }
            )
            .Build();

        _apiStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ApiResourceExt, bool>>>())
            .Returns(callInfo => apiResource1);

        // Act
        var result = new List<Claim>();
        await foreach (var claim in _mapper.MapApiRolesToClaimsAsync(apiName, clientId))
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
    public void ProcessCustomRole_YieldsClaim_WhenMappingIsValidAndMatches()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.ClientId, Value = "client" };
        var role = new ApiResourceRole { RoleName = "role", Mappings = new List<RoleMapping> { mapping } };

        // Act
        var claims = _mapper.ProcessCustomRole("api", role, "client").ToList();

        // Assert
        Assert.That(claims, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(claims[0].Type, Is.EqualTo(Abstraction.Constants.ClaimNames.UserRole));
            Assert.That(claims[0].Value, Is.EqualTo("role"));
        }
    }

    [Test]
    public void ProcessCustomRole_YieldsNoClaims_WhenMappingsNullOrEmpty()
    {
        // Arrange
        var roleWithNullMappings = new ApiResourceRole { RoleName = "role", Mappings = null };
        var roleWithEmptyMappings = new ApiResourceRole { RoleName = "role", Mappings = new List<RoleMapping>() };

        // Act
        var claimsNull = _mapper.ProcessCustomRole("api", roleWithNullMappings, "client").ToList();
        var claimsEmpty = _mapper.ProcessCustomRole("api", roleWithEmptyMappings, "client").ToList();

        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(claimsNull, Is.Empty);
            Assert.That(claimsEmpty, Is.Empty);
        }
    }

    [Test]
    public void IsValidRoleMapping_ReturnsFalse_WhenMappingIsNull()
    {
        // Arrange
        // (no additional setup needed)

        // Act
        var result = _mapper.IsValidRoleMapping("api", "role", null);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void IsValidRoleMapping_ReturnsFalse_WhenValueIsNullOrEmpty()
    {
        // Arrange
        var mappingEmpty = new RoleMapping { MappingType = RoleMapType.ClientId, Value = "" };
        var mappingNull = new RoleMapping { MappingType = RoleMapType.ClientId, Value = null! };

        // Act
        var resultEmpty = _mapper.IsValidRoleMapping("api", "role", mappingEmpty);
        var resultNull = _mapper.IsValidRoleMapping("api", "role", mappingNull);

        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(resultEmpty, Is.False);
            Assert.That(resultNull, Is.False);
        }
    }

    [Test]
    public void IsValidRoleMapping_ReturnsTrue_WhenValid()
    {
        // Arrange
        var mapping = new RoleMapping { MappingType = RoleMapType.ClientId, Value = "client" };

        // Act
        var result = _mapper.IsValidRoleMapping("api", "role", mapping);

        // Assert
        Assert.That(result, Is.True);
    }
}
