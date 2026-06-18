namespace IdentityServer.AdminPortal.Web.Models.Validation;

public interface IHasUniquePropertyValue
{
    string UniqueProperty { get; }
    HashSet<string> AlreadyExistingUniquePropertyValues { get; }
}
