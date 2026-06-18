using System.Text.Json;
using Microsoft.JSInterop;

namespace IdentityServer.AdminPortal.Web.Services.Storage;

public abstract class BaseStorageService : IJSStorageService
{
    private readonly IJSRuntime _jsRuntime;
    private readonly string _jsFunctionGet;
    private readonly string _jsFunctionSet;
    private readonly string _jsFunctionRemove;

    protected BaseStorageService(IJSRuntime jsRuntime, string jsFunctionStorageName)
    {
        _jsRuntime = jsRuntime;
        _jsFunctionGet = jsFunctionStorageName + ".getItem";
        _jsFunctionSet = jsFunctionStorageName + ".setItem";
        _jsFunctionRemove = jsFunctionStorageName + ".removeItem";
    }

    public ValueTask SetItem(string key, object data)
    {
        return _jsRuntime.InvokeVoidAsync(_jsFunctionSet, key, JsonSerializer.Serialize(data));
    }

    public async Task<T?> GetItem<T>(string key)
    {
        var data = await _jsRuntime.InvokeAsync<string>(_jsFunctionGet, key);

        if (!string.IsNullOrEmpty(data))
        {
            return JsonSerializer.Deserialize<T>(data);
        }

        return default;
    }

    public ValueTask RemoveItem(string key)
    {
        return _jsRuntime.InvokeVoidAsync(_jsFunctionRemove, key);
    }

    public ValueTask<string?> GetString(string key)
    {
        return _jsRuntime.InvokeAsync<string?>(_jsFunctionGet, key);
    }

    public ValueTask SetString(string key, string? value)
    {
        return _jsRuntime.InvokeVoidAsync(_jsFunctionSet, key, value);
    }
}
