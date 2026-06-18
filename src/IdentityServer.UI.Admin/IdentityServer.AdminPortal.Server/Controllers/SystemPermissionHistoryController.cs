using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.AdminPortal.Server.Controllers;

/// <summary>
/// Controller for retrieving system permission change history.
/// </summary>
[Route("api/systempermissions")]
public class SystemPermissionHistoryController : HistoryControllerBase
{
    public SystemPermissionHistoryController(ISystemPermissionHistoryRepository historyRepository)
        : base(historyRepository)
    {
    }
}
