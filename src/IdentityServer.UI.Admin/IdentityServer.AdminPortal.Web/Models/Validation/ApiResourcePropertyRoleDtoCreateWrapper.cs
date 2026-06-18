using System.Runtime.Serialization;
using IdentityServer.Abstraction.DTO.ApiResources;

namespace IdentityServer.AdminPortal.Web.Models.Validation;

[UniquePropertyValue(nameof(RoleName), "Role")]
public class ApiResourcePropertyRoleDtoCreateWrapper : ApiResourcePropertyRoleDtoCreate, IHasUniquePropertyValue
{
    [IgnoreDataMember]
    public HashSet<string> AlreadyExistingUniquePropertyValues { get; set; } = new();

    [IgnoreDataMember]
    public string UniqueProperty => RoleName;
}
