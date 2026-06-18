namespace IdentityServer.Abstraction.Contracts.MicrosoftGraph;

public interface IUserGroupMembershipService
{
    Task<bool> IsReaderOrContributorAsync(string userObjectId);

    Task<bool> IsContributorAsync(string userObjectId);
}