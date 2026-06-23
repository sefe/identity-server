// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;
using System.Security.Claims;
using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;
using IdentityServer.Services.ClientRoles;
using IdentityServer.Tests.Common.Builders;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Test.Services.ClientRoles;

[TestFixture]
public class ClientUserRoleClaimMapperTests
{
    private IStorage<ClientExt> _clientStorage;
    private IEntraUserService _entraService;
    private ClientUserRoleClaimMapper _sut;

    [SetUp]
    public void SetUp()
    {
        _clientStorage = Substitute.For<IStorage<ClientExt>>();
        _entraService = Substitute.For<IEntraUserService>();
        _sut = new ClientUserRoleClaimMapper(_clientStorage, _entraService, NullLogger<ClientUserRoleClaimMapper>.Instance);
    }

    [Test]
    public async Task ProcessClientRoleMappingsForUserAsync_ClientNotFound_YieldsNothing()
    {
        // Arrange
        _clientStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns((ClientExt)null);

        // Act
        var result = _sut.ProcessClientRoleMappingsForUserAsync("client1", "user1");
        var claims = new List<Claim>();
        await foreach (var claim in result)
        {
            claims.Add(claim);
        }

        // Assert
        Assert.That(claims, Is.Empty);
    }

    [Test]
    public async Task ProcessClientRoleMappingsForUserAsync_ClientHasNoRoles_YieldsNothing()
    {
        // Arrange
        const string ClientId = "client1";
        var client = new ClientExtBuilder(ClientId, "Client 1")
            .Build();
        _clientStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns(client);

        // Act
        var result = _sut.ProcessClientRoleMappingsForUserAsync(ClientId, "user1");
        var claims = new List<Claim>();
        await foreach (var claim in result)
        {
            claims.Add(claim);
        }

        // Assert
        Assert.That(claims, Is.Empty);
    }

    [Test]
    public async Task ProcessClientRoleMappingsForUserAsync_ClientRolesHaveNoMappings_YieldsNothing()
    {
        // Arrange
        const string ClientId = "client1";
        var client = new ClientExtBuilder(ClientId, "Client 1")
            .WithRole("role1", new List<ClientRoleMapping>())
            .Build();
        _clientStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns(client);

        // Act
        var result = _sut.ProcessClientRoleMappingsForUserAsync(ClientId, "user1");
        var claims = new List<Claim>();
        await foreach (var claim in result)
        {
            claims.Add(claim);
        }

        // Assert
        Assert.That(claims, Is.Empty);
    }

    [Test]
    public async Task ProcessClientRoleMappingsForUserAsync_ValidSecurityGroupMapping_YieldsClaim()
    {
        // Arrange
        const string ClientId = "client1";
        var mapping = new ClientRoleMapping
        {
            MappingType = ClientRoleMapType.SecurityGroup,
            Value = "group1"
        };
        var client = new ClientExtBuilder(ClientId, "Client 1")
            .WithRole("role1", new List<ClientRoleMapping> { mapping })
            .Build();
        _clientStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns(client);

        _entraService.GetUserMembershipInGroups("user1", Arg.Any<IEnumerable<string>>())
            .Returns(Task.FromResult(new List<Group> { new() { Id = "group1" } }));

        // Act
        var result = _sut.ProcessClientRoleMappingsForUserAsync(ClientId, "user1");
        var claims = new List<Claim>();
        await foreach (var claim in result)
        {
            claims.Add(claim);
        }

        // Assert
        Assert.That(claims, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(claims[0].Type, Is.EqualTo(ClaimNames.UserRole));
            Assert.That(claims[0].Value, Is.EqualTo("role1"));
        }
    }

    [Test]
    public async Task ProcessClientRoleMappingsForUserAsync_ValidUserObjectIdMapping_YieldsClaim()
    {
        // Arrange
        const string ClientId = "client1";
        var mapping = new ClientRoleMapping
        {
            MappingType = ClientRoleMapType.UserObjectId,
            Value = "user1"
        };
        var client = new ClientExtBuilder(ClientId, "Client 1")
            .WithRole("role2", new List<ClientRoleMapping> { mapping })
            .Build();
        _clientStorage.FirstOrDefaultAsync(Arg.Any<Expression<Func<ClientExt, bool>>>()).Returns(client);

        // No group membership needed for UserObjectId mapping
        _entraService.GetUserMembershipInGroups("user1", Arg.Any<IEnumerable<string>>())
            .Returns(Task.FromResult(new List<Group>()));

        // Act
        var result = _sut.ProcessClientRoleMappingsForUserAsync(ClientId, "user1");
        var claims = new List<Claim>();
        await foreach (var claim in result)
        {
            claims.Add(claim);
        }

        // Assert
        Assert.That(claims, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(claims[0].Type, Is.EqualTo(ClaimNames.UserRole));
            Assert.That(claims[0].Value, Is.EqualTo("role2"));
        }
    }

    [Test]
    public void GetSecurityGroupIdsFromRoleMappings_ReturnsCorrectGroupIds()
    {
        // Arrange
        const string ClientId = "client1";
        var mappings = new List<ClientRoleMapping>
        {
            new() { MappingType = ClientRoleMapType.SecurityGroup, Value = "group1" },
            new() { MappingType = ClientRoleMapType.SecurityGroup, Value = "group2" },
            new() { MappingType = ClientRoleMapType.UserObjectId, Value = "user1" },
            new() { MappingType = ClientRoleMapType.SecurityGroup, Value = "group1" } // duplicate
        };
        var client = new ClientExtBuilder(ClientId, "Client 1")
            .WithRole("role1", mappings)
            .Build();
        var expectedGroups = new List<string> { "group1", "group2" };

        // Act
        var result = ClientUserRoleClaimMapper.GetSecurityGroupIdsFromRoleMappings(client);

        // Assert
        Assert.That(result, Is.EquivalentTo(expectedGroups));
    }

    [Test]
    public async Task GetUserMembershipInMappedGroupsAsync_WithGroups_ReturnsHashSet()
    {
        // Arrange
        var groupIds = new List<string> { "group1", "group2" };
        _entraService.GetUserMembershipInGroups("user1", groupIds)
            .Returns(Task.FromResult(new List<Group> { new() { Id = "group1" } }));

        // Act
        var result = await _sut.GetUserMembershipInMappedGroupsAsync("user1", groupIds);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Does.Contain("group1"));
            Assert.That(result, Has.Count.EqualTo(1));
        }
    }

    [Test]
    public async Task GetUserMembershipInMappedGroupsAsync_EmptyGroups_ReturnsEmptyHashSet()
    {
        // Arrange
        var groupIds = new List<string>();

        // Act
        var result = await _sut.GetUserMembershipInMappedGroupsAsync("user1", groupIds);

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public void MapClientRolesToClaims_MapsClaimsCorrectly()
    {
        // Arrange
        var mapping = new ClientRoleMapping
        {
            MappingType = ClientRoleMapType.SecurityGroup,
            Value = "group1"
        };
        var role = new ClientRole
        {
            RoleName = "role1",
            Mappings = new List<ClientRoleMapping> { mapping }
        };
        var roles = new List<ClientRole> { role };
        var userMembershipGroups = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "group1" };

        // Act
        var result = _sut.MapClientRolesToClaims(roles, "client1", "user1", userMembershipGroups).ToList();

        // Assert
        Assert.That(result, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result[0].Type, Is.EqualTo(ClaimNames.UserRole));
            Assert.That(result[0].Value, Is.EqualTo("role1"));
        }
    }

    [Test]
    public void ProcessCustomRole_ValidMapping_YieldsClaim()
    {
        // Arrange
        var mapping = new ClientRoleMapping
        {
            MappingType = ClientRoleMapType.SecurityGroup,
            Value = "group1"
        };
        var role = new ClientRole
        {
            RoleName = "role1",
            Mappings = new List<ClientRoleMapping> { mapping }
        };
        var userMembershipGroups = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "group1" };

        // Act
        var result = _sut.ProcessCustomRole(role, "client1", "user1", userMembershipGroups).ToList();

        // Assert
        Assert.That(result, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result[0].Type, Is.EqualTo(ClaimNames.UserRole));
            Assert.That(result[0].Value, Is.EqualTo("role1"));
        }
    }

    [Test]
    public void IsValidRoleMapping_NullMapping_ReturnsFalse()
    {
        // Arrange

        // Act
        var result = _sut.IsValidRoleMapping("client1", "role1", null);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void IsValidRoleMapping_EmptyValue_ReturnsFalse()
    {
        // Arrange
        var mapping = new ClientRoleMapping { Value = "", MappingType = ClientRoleMapType.SecurityGroup };

        // Act
        var result = _sut.IsValidRoleMapping("client1", "role1", mapping);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void IsValidRoleMapping_ValidMapping_ReturnsTrue()
    {
        // Arrange
        var mapping = new ClientRoleMapping { Value = "group1", MappingType = ClientRoleMapType.SecurityGroup };

        // Act
        var result = _sut.IsValidRoleMapping("client1", "role1", mapping);

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void HasMappingMatch_SecurityGroupType_ReturnsTrueIfGroupMatches()
    {
        // Arrange
        var mapping = new ClientRoleMapping { MappingType = ClientRoleMapType.SecurityGroup, Value = "group1" };
        var userMembershipGroups = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "group1" };

        // Act
        var result = _sut.HasMappingMatch(mapping, "user1", userMembershipGroups, "client1", "role1");

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void HasMappingMatch_UserObjectIdType_ReturnsTrueIfUserMatches()
    {
        // Arrange
        var mapping = new ClientRoleMapping { MappingType = ClientRoleMapType.UserObjectId, Value = "user1" };
        var userMembershipGroups = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Act
        var result = _sut.HasMappingMatch(mapping, "user1", userMembershipGroups, "client1", "role1");

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void HasMappingMatch_UnsupportedType_ReturnsFalse()
    {
        // Arrange
        var mapping = new ClientRoleMapping { MappingType = (ClientRoleMapType)999, Value = "val" };
        var userMembershipGroups = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Act
        var result = _sut.HasMappingMatch(mapping, "user1", userMembershipGroups, "client1", "role1");

        // Assert
        Assert.That(result, Is.False);
    }
}
