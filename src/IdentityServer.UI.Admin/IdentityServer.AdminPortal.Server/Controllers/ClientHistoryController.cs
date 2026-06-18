using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.AdminPortal.Server.Controllers;

/// <summary>
/// Controller for retrieving client change history.
/// </summary>
[Route("api/applications")]
public class ClientHistoryController : HistoryControllerBase
{
    public ClientHistoryController(IClientHistoryRepository historyRepository)
        : base(historyRepository)
    {
    }
}
