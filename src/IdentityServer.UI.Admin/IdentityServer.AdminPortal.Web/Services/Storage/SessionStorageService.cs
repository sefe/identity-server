using Microsoft.JSInterop;

namespace IdentityServer.AdminPortal.Web.Services.Storage;

public class SessionStorageService : BaseStorageService
{
    public SessionStorageService(IJSRuntime jsRuntime) : base(jsRuntime, "sessionStorage")
    {
    }
}
