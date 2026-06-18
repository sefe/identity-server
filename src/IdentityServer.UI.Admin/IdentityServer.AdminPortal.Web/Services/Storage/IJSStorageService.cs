namespace IdentityServer.AdminPortal.Web.Services.Storage;

public interface IJSStorageService
{
    Task<T?> GetItem<T>(string key);
    ValueTask RemoveItem(string key);
    ValueTask SetItem(string key, object data);
    ValueTask<string?> GetString(string key);
    ValueTask SetString(string key, string? value);
}
