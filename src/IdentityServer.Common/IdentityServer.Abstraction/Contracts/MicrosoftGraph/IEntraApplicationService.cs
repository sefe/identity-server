using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.Abstraction.Contracts.MicrosoftGraph;

public interface IEntraApplicationService
{
    Task<Application?> GetByIdAsync(string appId);
}
