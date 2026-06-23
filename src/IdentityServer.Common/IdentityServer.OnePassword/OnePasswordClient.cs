// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Net.Http.Headers;
using System.Text.Json;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.OnePassword;

public class OnePasswordClient
{
    private const string _getItemUriFormat = "{0}/v1/vaults/{1}/items/{2}";

    private readonly OnePasswordConfig _config;
    private readonly HttpClient _httpClient;
    private readonly string _baseUri;

    public OnePasswordClient(HttpClient httpClient, OnePasswordConfig config)
    {
        _config = config;
        _httpClient = httpClient;
        _baseUri = config.BaseUrl.TrimEnd('/');
        _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", config.AccessToken);
    }

    public async Task<string?> GetSecretValueAsync(string itemId)
    {
        OnePasswordItem? secretItem = await GetItemAsync(_config.VaultId, itemId);
        if (secretItem != null)
        {
            return (secretItem.Category?.ToUpper()) switch
            {
                OnePasswordItem.CredentialCategory => secretItem.GetFieldValue(OnePasswordField.CredentialFieldId),
                OnePasswordItem.LoginCategory => secretItem.GetFieldValue(OnePasswordField.PasswordFieldId),
                _ => throw new IdentityServerException($"'{secretItem.Category}' category is not supported. Vault '{_config.VaultId}', item '{itemId}'.")
            };
        }

        throw new IdentityServerException($"Request for vault '{_config.VaultId}' item '{itemId}' resulted in empty response.");
    }

    private async Task<OnePasswordItem?> GetItemAsync(string vaultId, string itemId)
    {
        Uri uri = new(string.Format(_getItemUriFormat, _baseUri, vaultId, itemId));
        HttpResponseMessage response = await _httpClient.GetAsync(uri);

        var responseContent = await ReadHttpResponseAsStringAsync(response);
        if (!response.IsSuccessStatusCode)
        {
            throw new IdentityServerException($"Error fetching item '{itemId}' in vault '{vaultId}' from 1Password. Status code: {response.StatusCode}. Response: {responseContent}");
        }

        try
        {
            return JsonSerializer.Deserialize<OnePasswordItem>(responseContent);
        }
        catch (Exception ex)
        {
            throw new IdentityServerException($"Failed to deserialize 1Password response for item '{itemId}' in vault '{vaultId}'. Response: {responseContent}", ex);
        }
    }

    private static async Task<string> ReadHttpResponseAsStringAsync(HttpResponseMessage response)
    {
        try
        {
            return await response.Content.ReadAsStringAsync();
        }
        catch { /* Ignore */}
        return string.Empty;
    }
}
