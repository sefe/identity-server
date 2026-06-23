// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.AdminPortal.Web.Models.RoleImport;
using IdentityServer.AdminPortal.Web.Services.RoleImport;

namespace IdentityServer.AdminPortal.Test.Services.RoleImport;

[TestFixture]
public class RoleAddComparerTests
{
    private const string _role1Name = "TestRole1";
    private const string _role2Name = "TestRole2";

    private static class RoleMapTypeStrings
    {
        public const string UserObjectId = "UserObjectId";
        public const string ClientId = "ClientId";
        public const string SecurityGroup = "SecurityGroup";
    }

    private static RoleValueObject<ApiResourceRoleMappingValueObject> MakeRole(string name, params ApiResourceRoleMappingValueObject[] mappings) =>
        new()
        {
            RoleName = name,
            Mappings = mappings.ToList()
        };

    private static ApiResourceRoleMappingValueObject MakeMapping(string type, string value, string desc = null) =>
        new()
        {
            MappingType = type,
            Value = value,
            Description = desc
        };

    [Test]
    public async Task CompareRoles_EmptyLists_ReturnsEmpty()
    {
        var result = await RoleAddComparer.CompareRolesAsync(new List<RoleValueObject<ApiResourceRoleMappingValueObject>>(), new List<RoleValueObject<ApiResourceRoleMappingValueObject>>());
        Assert.That(result, Is.Empty);
    }

    [Test]
    public async Task CompareRoles_RoleOnlyInExisting_ReturnsUnchanged()
    {
        var existing = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { MakeRole(_role1Name) };
        var imported = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>();
        var result = await RoleAddComparer.CompareRolesAsync(existing, imported);
        Assert.That(result, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result[0].RoleName, Is.EqualTo(_role1Name));
            Assert.That(result[0].RoleState, Is.EqualTo(ComparisonState.Unchanged));
        }
    }

    [Test]
    public async Task CompareRoles_RoleOnlyInImport_ReturnsAdded()
    {
        var existing = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>();
        var imported = new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { MakeRole(_role2Name) };
        var result = await RoleAddComparer.CompareRolesAsync(existing, imported);
        Assert.That(result, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result[0].RoleName, Is.EqualTo(_role2Name));
            Assert.That(result[0].RoleState, Is.EqualTo(ComparisonState.Added));
        }
    }

    [Test]
    public async Task CompareRoles_RoleInBothWithUnchangedMappings_ReturnsUnchanged()
    {
        var existing = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>
        {
            MakeRole(_role1Name, MakeMapping(RoleMapTypeStrings.UserObjectId, "1", "desc"))
        };
        var imported = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>
        {
            MakeRole(_role1Name, MakeMapping(RoleMapTypeStrings.UserObjectId, "1", "desc"))
        };
        var result = await RoleAddComparer.CompareRolesAsync(existing, imported);
        Assert.That(result, Has.Count.EqualTo(1));
        var role = result[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(role.RoleName, Is.EqualTo(_role1Name));
            Assert.That(role.RoleState, Is.EqualTo(ComparisonState.Unchanged));
            Assert.That(role.RoleMappingState, Is.EqualTo(ComparisonState.Unchanged));
        }
        var mappings = role.Mappings;
        Assert.That(mappings, Has.Count.EqualTo(1));
        Assert.That(mappings[0].State, Is.EqualTo(ComparisonState.Unchanged));
    }

    [Test]
    public async Task CompareRoles_RoleInBothWithChangedMappingDescription_ReturnsConflict()
    {
        var existing = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>
        {
            MakeRole(_role1Name, MakeMapping(RoleMapTypeStrings.UserObjectId, "1", "desc1"))
        };
        var imported = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>
        {
            MakeRole(_role1Name, MakeMapping(RoleMapTypeStrings.UserObjectId, "1", "desc2"))
        };
        var result = await RoleAddComparer.CompareRolesAsync(existing, imported);
        Assert.That(result, Has.Count.EqualTo(1));
        var role = result[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(role.RoleName, Is.EqualTo(_role1Name));
            Assert.That(role.RoleState, Is.EqualTo(ComparisonState.Unchanged));
            Assert.That(role.RoleMappingState, Is.EqualTo(ComparisonState.Conflict));
        }
        var mappings = role.Mappings;
        Assert.That(mappings, Has.Count.EqualTo(1));
        Assert.That(mappings[0].State, Is.EqualTo(ComparisonState.Conflict));
    }

    [Test]
    public async Task CompareRoles_RoleInBothWithAddedMappings()
    {
        var existing = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>
        {
            MakeRole(_role1Name,
                MakeMapping(RoleMapTypeStrings.UserObjectId, "1", "desc1"),
                MakeMapping(RoleMapTypeStrings.ClientId, "2", "desc2"))
        };
        var imported = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>
        {
            MakeRole(_role1Name,
                MakeMapping(RoleMapTypeStrings.UserObjectId, "1", "desc1"),
                MakeMapping(RoleMapTypeStrings.SecurityGroup, "3", "desc3"))
        };
        var result = await RoleAddComparer.CompareRolesAsync(existing, imported);
        Assert.That(result, Has.Count.EqualTo(1));
        var role = result[0];
        using (Assert.EnterMultipleScope())
        {
            Assert.That(role.RoleName, Is.EqualTo(_role1Name));
            Assert.That(role.RoleState, Is.EqualTo(ComparisonState.Unchanged));
            Assert.That(role.RoleMappingState, Is.EqualTo(ComparisonState.Mixed));
        }
        var mappings = role.Mappings;
        using (Assert.EnterMultipleScope())
        {
            Assert.That(mappings.Any(m => m.State == ComparisonState.Unchanged && m.Existing.MappingType == RoleMapTypeStrings.ClientId), Is.True);
            Assert.That(mappings.Any(m => m.State == ComparisonState.Unchanged && m.Existing.MappingType == RoleMapTypeStrings.UserObjectId), Is.True);
            Assert.That(mappings.Any(m => m.State == ComparisonState.Added && m.Imported.MappingType == RoleMapTypeStrings.SecurityGroup), Is.True);
        }
    }

    [Test]
    public void CompareRoles_RoleWithNullMappings_DoesNotThrow()
    {
        var existing = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>
        {
            new() { RoleName = _role1Name, Mappings = null! }
        };
        var imported = new List<RoleValueObject<ApiResourceRoleMappingValueObject>>
        {
            new() { RoleName = _role1Name, Mappings = null! }
        };
        Assert.DoesNotThrowAsync(() => RoleAddComparer.CompareRolesAsync(existing, imported));
    }
}
