namespace IdentityServer.AdminPortal.Web.Services.Search;

public abstract class AdminApiProviderBase
{
    protected readonly IAdminApiService AdminApi;

    protected AdminApiProviderBase(IAdminApiService adminApi)
    {
        AdminApi = adminApi;
    }
}
