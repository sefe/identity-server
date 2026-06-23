// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;

namespace IdentityServer.AdminPortal.Test.Services.RoleImport;

[TestFixture]
public class RoleImportDtoValidationService_ApiResource_Tests
{
    private const string _role1Name = "TestRole1";
    private const string _role2Name = "TestRole2";

    private static ApiResourceRoleImportDto MakeImportDto(List<RoleValueObject<ApiResourceRoleMappingValueObject>> roles) => new() { Roles = roles, ImportStrategy = ImportStrategy.Add };

    private static RoleValueObject<ApiResourceRoleMappingValueObject> MakeRole(string name, params ApiResourceRoleMappingValueObject[] mappings) => new()
    { RoleName = name, Mappings = new List<ApiResourceRoleMappingValueObject>(mappings) };

    private static ApiResourceRoleMappingValueObject MakeMapping(string type, string value, string desc) => new()
    { MappingType = type, Value = value, Description = desc };

    // Helper to match the new Validate signature
    private static bool Validate(ApiResourceRoleImportDto dto, out string error)
    {
        var status = new OperationStatus();
        var result = RoleImportDtoValidationService<ApiResourceRoleMappingValueObject>.IsValid(dto, status);
        error = string.Join("; ", status.Errors);
        return result;
    }

    [Test]
    public void Validate_NullImportDto_ReturnsFalse()
    {
        var result = Validate(null, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            Assert.That(error, Does.Contain("cannot be null"));
        }
    }

    [Test]
    public void Validate_EmptyRoles_ReturnsFalse()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>>());
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            Assert.That(error, Does.Contain("no roles"));
        }
    }

    [Test]
    public void Validate_RoleWithNullName_ReturnsFalse()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> { new() { RoleName = null!, Mappings = new List<ApiResourceRoleMappingValueObject>() } });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            Assert.That(error, Does.Contain("invalid and/or lacks a valid role name"));
        }
    }

    [Test]
    public void Validate_DuplicateRoleNames_ReturnsFalse()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name),
            MakeRole(_role1Name)
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            Assert.That(error, Does.Contain("Duplicate role names"));
        }
    }

    [Test]
    public void Validate_MappingMissingFields_MappingType_ReturnsFalse()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name, new ApiResourceRoleMappingValueObject { MappingType = null!, Value = "v", Description = "d" })
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            Assert.That(error, Does.Contain("required for each mapping"));
        }
    }

    [Test]
    public void Validate_MappingMissingFields_Value_ReturnsFalse()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name, new ApiResourceRoleMappingValueObject { MappingType = nameof(RoleMapType.SecurityGroup), Value = null!, Description = "d" })
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            Assert.That(error, Does.Contain("required for each mapping"));
        }
    }

    [Test]
    public void Validate_MappingMissingFields_Description_ReturnsTrue()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name, new ApiResourceRoleMappingValueObject { MappingType = nameof(RoleMapType.SecurityGroup), Value = "v", Description = null! })
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            Assert.That(error, Is.Empty);
        }
    }

    [Test]
    public void Validate_DuplicateMappingValuesWithinRole_ReturnsFalse()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name,
                MakeMapping("Type1", "Val1", "Desc1"),
                MakeMapping("Type1", "Val1", "Desc2"))
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.False);
            Assert.That(error, Does.Contain("Duplicate mapping values"));
        }
    }

    [Test]
    public void Validate_DuplicateMappingDescriptionsWithinRole_ReturnsTrue()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name,
                MakeMapping("Type1", "Val1", "Desc1"),
                MakeMapping("Type1", "Val2", "Desc1"))
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            Assert.That(error, Is.Empty);
        }
    }

    [Test]
    public void Validate_DuplicateDescriptionsAcrossRoles_IsNotInconsistent_ReturnsTrue()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name, MakeMapping("Type1", "Val1", "Desc1")),
            MakeRole(_role2Name, MakeMapping("Type1", "Val2", "Desc1"))
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            Assert.That(error, Is.Empty);
        }
    }

    [Test]
    public void Validate_EmptyDescriptionsAcrossRoles_IsNotInconsistent_ReturnsTrue()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name, MakeMapping("Type1", "Val1", null!)),
            MakeRole(_role2Name, MakeMapping("Type1", "Val1", string.Empty))
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            Assert.That(error, Is.Empty);
        }
    }

    [Test]
    public void Validate_DifferentDescriptionsForValueAcrossRoles_IsNotInconsistent_ReturnsTrue()
    {
        // inconsistent dscriptions will trigger server-side validation warning
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name, MakeMapping("Type1", "Val1", "Desc1")),
            MakeRole(_role2Name, MakeMapping("Type1", "Val1", "Desc2"))
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            Assert.That(error, Is.Empty);
        }
    }

    [Test]
    public void Validate_ValidInput_ReturnsTrue()
    {
        var dto = MakeImportDto(new List<RoleValueObject<ApiResourceRoleMappingValueObject>> {
            MakeRole(_role1Name, MakeMapping("Type1", "Val1", "Desc1")),
            MakeRole(_role2Name, MakeMapping("Type1", "Val2", "Desc2"))
        });
        var result = Validate(dto, out var error);
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.True);
            Assert.That(error, Is.Empty);
        }
    }
}
