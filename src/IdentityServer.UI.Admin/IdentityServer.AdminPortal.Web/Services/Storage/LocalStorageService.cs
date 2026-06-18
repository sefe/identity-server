using Microsoft.JSInterop;

namespace IdentityServer.AdminPortal.Web.Services.Storage;

public class LocalStorageService : BaseStorageService
{
    public LocalStorageService(IJSRuntime jsRuntime) : base(jsRuntime, "localStorage")
    {
    }
}
