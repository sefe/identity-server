using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public static class SystemPermissionRelationshipTestCases
{
    /// <summary>
    /// Cannot create unbound entities
    /// </summary>
    public static IEnumerable<TestCaseData> SystemPermissionCreateUnboundData
    {
        get
        {
            yield return new TestCaseData(TestUser.Reader.Identity.Name, SystemPermissionRoleType.Writer);
            yield return new TestCaseData(TestUser.Contributor.Identity.Name, SystemPermissionRoleType.Writer);
            yield return new TestCaseData(TestUser.Admin.Identity.Name, SystemPermissionRoleType.None);
        }
    }

    /// <summary>
    /// Cannot create role for a random user
    /// </summary>
    public static IEnumerable<TestCaseData> SystemPermissionCreateUserRoleData
    {
        get
        {
            // Readers cannot create role assignments
            yield return new TestCaseData(TestUser.Contributor.Identity.Name, SystemPermissionRoleType.Writer);
            yield return new TestCaseData(TestUser.Admin.Identity.Name, SystemPermissionRoleType.None);
        }
    }

    /// <summary>
    /// Relationship blocks Deletion
    /// </summary>
    public static IEnumerable<TestCaseData> DeleteSystemPermissionWithRelationship
    {
        get
        {
            yield return new TestCaseData(TestUser.Reader.Identity.Name, SystemPermissionRoleType.None, typeof(EntityAccessException));
            yield return new TestCaseData(TestUser.Reader.Identity.Name, SystemPermissionRoleType.Writer, typeof(EntityAccessException));
            yield return new TestCaseData(TestUser.Contributor.Identity.Name, SystemPermissionRoleType.None, typeof(EntityAccessException));
            yield return new TestCaseData(TestUser.Contributor.Identity.Name, SystemPermissionRoleType.Writer, typeof(EntityReferenceException));
            yield return new TestCaseData(TestUser.Admin.Identity.Name, SystemPermissionRoleType.None, typeof(EntityReferenceException));
            yield return new TestCaseData(TestUser.Admin.Identity.Name, SystemPermissionRoleType.Writer, typeof(EntityReferenceException));
        }
    }

    /// <summary>
    /// No Relationship allows deletion
    /// </summary>
    public static IEnumerable<TestCaseData> DeleteSystemPermissionNoRelationship
    {
        get
        {
            yield return new TestCaseData(TestUser.Reader.Identity.Name, SystemPermissionRoleType.None, typeof(EntityAccessException));
            yield return new TestCaseData(TestUser.Reader.Identity.Name, SystemPermissionRoleType.Writer, typeof(EntityAccessException));
            yield return new TestCaseData(TestUser.Contributor.Identity.Name, SystemPermissionRoleType.None, typeof(EntityAccessException));
            yield return new TestCaseData(TestUser.Contributor.Identity.Name, SystemPermissionRoleType.Writer, null);
            yield return new TestCaseData(TestUser.Admin.Identity.Name, SystemPermissionRoleType.None, null);
            yield return new TestCaseData(TestUser.Admin.Identity.Name, SystemPermissionRoleType.Writer, null);
        }
    }
}
