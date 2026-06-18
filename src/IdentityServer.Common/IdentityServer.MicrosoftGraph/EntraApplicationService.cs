using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.MicrosoftGraph;

internal class EntraApplicationService : IEntraApplicationService
{
    private readonly IMicrosoftGraphApplicationApi _graphAppApi;

    public EntraApplicationService(IMicrosoftGraphApplicationApi graphAppApi)
    {
        _graphAppApi = graphAppApi;
    }

    public Task<Application?> GetByIdAsync(string appId)
    {
        return _graphAppApi.GetApplicationByAppIdAsync(appId);
    }
}
