// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Net.Http.Json;
using Telerik.DataSource;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.DTO.SystemPermissions;
using IdentityServer.Abstraction.Entities;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Web.Models;

namespace IdentityServer.AdminPortal.Web.Services;

public class AdminApiService : IAdminApiService
{
    public const string HttpClientName = "AdminApi";

    public const string GenericErrorMessage = "Operation failed. Please contact the administrator.";
    public const string UnexpectedErrorMessage = "Operation completed abnormally. Please contact the administrator.";

    private readonly HttpClient _client;

    public AdminApiService(IHttpClientFactory clientFactory)
    {
        _client = clientFactory.CreateClient(HttpClientName);
    }

    public Task<ApiCallResult<SystemPermissionDtoRead>> GetSystemPermission(int id)
        => Get<SystemPermissionDtoRead>($"api/systempermission/{id}");

    public Task<ApiCallResult<SystemPermissionDtoRead>> CreateSystemPermission(SystemPermissionDtoCreate systemPermission)
        => Post<SystemPermissionDtoCreate, SystemPermissionDtoRead>(systemPermission, "api/systempermission");

    public Task<ApiCallResult<SystemPermissionDtoRead>> UpdateSystemPermission(SystemPermissionDtoUpdate systemPermission)
        => Put<SystemPermissionDtoUpdate, SystemPermissionDtoRead>(systemPermission, "api/systempermission");

    public Task<ApiCallResult<int>> DeleteSystemPermission(SystemPermissionDtoRead systemPermission)
        => Delete<int>($"api/systempermission/{systemPermission.Id}");

    public Task<ApiCallResult<SystemPermissionEnvironmentDtoRead>> GetSystemPermissionEnvironment(int id)
        => Get<SystemPermissionEnvironmentDtoRead>($"api/systempermissionenvironment/{id}");

    public Task<ApiCallResult<string[]>> GetSystemPermissionEnvironmentContacts(int id)
        => Get<string[]>($"api/systempermissionenvironment/{id}/contacts");

    public Task<ApiCallResult<DataEnvelope<SystemPermissionEnvironmentDtoRead>>> GetSystemPermissionEnvironmentsPaged(DataSourceRequest request)
        => Post<DataSourceRequest, DataEnvelope<SystemPermissionEnvironmentDtoRead>>(request, "api/systempermissionenvironment/datasource");

    public Task<ApiCallResult<SystemPermissionDtoRead>> CreateSystemPermissionEnvironment(SystemPermissionEnvironmentDtoCreate env)
        => Post<SystemPermissionEnvironmentDtoCreate, SystemPermissionDtoRead>(env, "api/systempermissionenvironment");

    public Task<ApiCallResult<int>> DeleteSystemPermissionEnvironment(SystemPermissionEnvironmentDtoRead env)
        => Delete<int>($"api/systempermissionenvironment/{env.Id}");

    public Task<ApiCallResult<SystemPermissionRoleDtoRead>> CreateSystemPermissionRole(SystemPermissionRoleDtoCreate role)
        => Post<SystemPermissionRoleDtoCreate, SystemPermissionRoleDtoRead>(role, "api/systempermissionrole");

    public Task<ApiCallResult<SystemPermissionRoleDtoRead>> UpdateSystemPermissionRole(SystemPermissionRoleDtoUpdate role)
        => Put<SystemPermissionRoleDtoUpdate, SystemPermissionRoleDtoRead>(role, "api/systempermissionrole");

    public Task<ApiCallResult<int>> DeleteSystemPermissionRole(SystemPermissionRoleDtoRead role)
        => Delete<int>($"api/systempermissionrole/{role.Id}");

    public Task<ApiCallResult<ClientDtoRead>> GetClient(int id)
        => Get<ClientDtoRead>($"api/client/{id}");

    public Task<ApiCallResult<ClientDtoRead>> CreateClient(ClientDtoCreate app)
        => Post<ClientDtoCreate, ClientDtoRead>(app, "api/client");

    public Task<ApiCallResult<ClientDtoRead>> CloneClient(ClientDtoClone app)
        => Post<ClientDtoClone, ClientDtoRead>(app, "api/client/clone");

    public Task<ApiCallResult<ClientDtoRead>> UpdateClient(ClientDtoUpdate app)
        => Put<ClientDtoUpdate, ClientDtoRead>(app, "api/client");

    public Task<ApiCallResult<int>> DeleteClient(ClientDtoRead app)
        => Delete<int>($"api/client/{app.Id}");

    public Task<ApiCallResult<ClientPropertySecretValueDtoRead>> AddClientSecret(ClientPropertySecretDtoCreate secret)
        => Post<ClientPropertySecretDtoCreate, ClientPropertySecretValueDtoRead>(secret, "api/client/secret");

    public Task<ApiCallResult<int>> DeleteClientSecret(ClientPropertySecretDtoRead secret)
        => Delete<int>($"api/client/secret/{secret.Id}");

    public Task<ApiCallResult<ClientPropertyGrantDtoRead>> AddClientGrant(ClientPropertyGrantDtoCreate grant)
        => Post<ClientPropertyGrantDtoCreate, ClientPropertyGrantDtoRead>(grant, "api/client/grant");

    public Task<ApiCallResult<int>> DeleteClientGrant(ClientPropertyGrantDtoRead grant)
        => Delete<int>($"api/client/grant/{grant.Id}");

    public Task<ApiCallResult<ClientPropertyEntraAppDtoRead>> AddClientEntraApp(ClientPropertyEntraAppDtoCreate entraApp)
        => Post<ClientPropertyEntraAppDtoCreate, ClientPropertyEntraAppDtoRead>(entraApp, "api/client/entraapp");

    public Task<ApiCallResult<int>> DeleteClientEntraApp(ClientPropertyEntraAppDtoRead entraApp)
        => Delete<int>($"api/client/entraapp/{entraApp.Id}");

    public Task<ApiCallResult<ClientPropertyScopeDtoRead>> AddClientScope(ClientPropertyScopeDtoCreate scope)
        => Post<ClientPropertyScopeDtoCreate, ClientPropertyScopeDtoRead>(scope, "api/client/scope");

    public Task<ApiCallResult<int>> DeleteClientScope(ClientPropertyScopeDtoRead scope)
        => Delete<int>($"api/client/scope/{scope.Id}");

    public Task<ApiCallResult<ClientPropertyRedirectUriDtoRead>> AddClientRedirectUri(ClientPropertyRedirectUriDtoCreate redirect)
        => Post<ClientPropertyRedirectUriDtoCreate, ClientPropertyRedirectUriDtoRead>(redirect, "api/client/redirect");

    public Task<ApiCallResult<int>> DeleteClientRedirectUri(ClientPropertyRedirectUriDtoRead redirect)
        => Delete<int>($"api/client/redirect/{redirect.Id}");

    public Task<ApiCallResult<ClientPropertyPostLogoutRedirectUriDtoRead>> AddClientPostLogoutRedirectUri(ClientPropertyPostLogoutRedirectUriDtoCreate postLogoutRedirect)
        => Post<ClientPropertyPostLogoutRedirectUriDtoCreate, ClientPropertyPostLogoutRedirectUriDtoRead>(postLogoutRedirect, "api/client/postlogoutredirect");

    public Task<ApiCallResult<int>> DeleteClientPostLogoutRedirectUri(ClientPropertyPostLogoutRedirectUriDtoRead postLogoutRedirect)
        => Delete<int>($"api/client/postlogoutredirect/{postLogoutRedirect.Id}");

    public Task<ApiCallResult<ClientPropertyCorsOriginDtoRead>> AddClientCorsUri(ClientPropertyCorsOriginDtoCreate cors)
        => Post<ClientPropertyCorsOriginDtoCreate, ClientPropertyCorsOriginDtoRead>(cors, "api/client/cors");

    public Task<ApiCallResult<int>> DeleteClientCorsUri(ClientPropertyCorsOriginDtoRead cors)
        => Delete<int>($"api/client/cors/{cors.Id}");

    public Task<ApiCallResult<ClientPropertyRoleDtoRead>> AddClientRole(ClientPropertyRoleDtoCreate role)
    => Post<ClientPropertyRoleDtoCreate, ClientPropertyRoleDtoRead>(role, "api/client/role");

    public Task<ApiCallResult<int>> DeleteClientRole(ClientPropertyRoleDtoRead role)
        => Delete<int>($"api/client/role/{role.Id}");

    public Task<ApiCallResult<ClientPropertyRoleMappingDtoRead>> AddClientRoleMapping(ClientPropertyRoleMappingDtoCreate roleMapping)
        => Post<ClientPropertyRoleMappingDtoCreate, ClientPropertyRoleMappingDtoRead>(roleMapping, "api/client/rolemapping");

    public Task<ApiCallResult<int>> DeleteClientRoleMapping(ClientPropertyRoleMappingDtoRead roleMapping)
        => Delete<int>($"api/client/rolemapping/{roleMapping.Id}");

    public Task<ApiCallResult<OperationStatus>> ImportClientRoles(ClientDtoRead client, ClientRoleImportDto roles)
        => Put<ClientRoleImportDto, OperationStatus>(roles, $"api/clientimport/{client.Id}/roles");

    public Task<ApiCallResult<OperationStatus>> ValidateImportClientRoles(ClientDtoRead client, ClientRoleImportDto roles)
        => Post<ClientRoleImportDto, OperationStatus>(roles, $"api/clientimport/{client.Id}/roles/validation");

    public Task<ApiCallResult<HistoryResponseDto>> GetClientHistory(int clientId)
        => Get<HistoryResponseDto>($"api/applications/{clientId}/history");

    public Task<ApiCallResult<HistoryResponseDto>> GetSystemPermissionHistory(int systemPermissionId)
        => Get<HistoryResponseDto>($"api/systempermissions/{systemPermissionId}/history");

    public Task<ApiCallResult<HistoryResponseDto>> GetApiResourceHistory(int apiResourceId)
        => Get<HistoryResponseDto>($"api/apiresources/{apiResourceId}/history");

    public Task<ApiCallResult<ApiResourceDtoRead>> GetApiResource(int id)
        => Get<ApiResourceDtoRead>($"api/apiresource/{id}");

    public Task<ApiCallResult<ApiResourceDtoRead>> CreateApiResource(ApiResourceDtoCreate app)
        => Post<ApiResourceDtoCreate, ApiResourceDtoRead>(app, "api/apiresource");

    public Task<ApiCallResult<ApiResourceDtoRead>> CloneApiResource(ApiResourceDtoClone app)
        => Post<ApiResourceDtoClone, ApiResourceDtoRead>(app, "api/apiresource/clone");

    public Task<ApiCallResult<ApiResourceDtoRead>> UpdateApiResource(ApiResourceDtoUpdate app)
        => Put<ApiResourceDtoUpdate, ApiResourceDtoRead>(app, "api/apiresource");

    public Task<ApiCallResult<int>> DeleteApiResource(ApiResourceDtoRead api)
        => Delete<int>($"api/apiresource/{api.Id}");

    public Task<ApiCallResult<ApiResourcePropertySecretValueDtoRead>> AddApiResourceSecret(ApiResourcePropertySecretDtoCreate secret)
    => Post<ApiResourcePropertySecretDtoCreate, ApiResourcePropertySecretValueDtoRead>(secret, "api/apiresource/secret");

    public Task<ApiCallResult<int>> DeleteApiResourceSecret(ApiResourcePropertySecretDtoRead secret)
        => Delete<int>($"api/apiresource/secret/{secret.Id}");

    public Task<ApiCallResult<ApiResourcePropertyScopeDtoRead>> AddApiResourceScope(ApiResourcePropertyScopeDtoCreate scope)
        => Post<ApiResourcePropertyScopeDtoCreate, ApiResourcePropertyScopeDtoRead>(scope, "api/apiresource/scope");

    public Task<ApiCallResult<ApiResourcePropertyScopeDtoRead>> UpdateApiResourceScope(ApiResourcePropertyScopeDtoUpdate scope)
        => Put<ApiResourcePropertyScopeDtoUpdate, ApiResourcePropertyScopeDtoRead>(scope, "api/apiresource/scope");

    public Task<ApiCallResult<int>> DeleteApiResourceScope(ApiResourcePropertyScopeDtoRead scope)
        => Delete<int>($"api/apiresource/scope/{scope.Id}");

    public Task<ApiCallResult<ApiResourcePropertyRoleDtoRead>> AddApiResourceRole(ApiResourcePropertyRoleDtoCreate role)
        => Post<ApiResourcePropertyRoleDtoCreate, ApiResourcePropertyRoleDtoRead>(role, "api/apiresource/role");

    public Task<ApiCallResult<int>> DeleteApiResourceRole(ApiResourcePropertyRoleDtoRead role)
        => Delete<int>($"api/apiresource/role/{role.Id}");

    public Task<ApiCallResult<ApiResourcePropertyRoleMappingDtoRead>> AddApiResourceRoleMapping(ApiResourcePropertyRoleMappingDtoCreate roleMapping)
        => Post<ApiResourcePropertyRoleMappingDtoCreate, ApiResourcePropertyRoleMappingDtoRead>(roleMapping, "api/apiresource/rolemapping");

    public Task<ApiCallResult<int>> DeleteApiResourceRoleMapping(ApiResourcePropertyRoleMappingDtoRead roleMapping)
        => Delete<int>($"api/apiresource/rolemapping/{roleMapping.Id}");

    public Task<ApiCallResult<OperationStatus>> ImportApiResourceRoles(ApiResourceDtoRead apiResource, ApiResourceRoleImportDto roles)
        => Put<ApiResourceRoleImportDto, OperationStatus>(roles, $"api/apiresourceimport/{apiResource.Id}/roles");

    public Task<ApiCallResult<OperationStatus>> ValidateImportApiResourceRoles(ApiResourceDtoRead apiResource, ApiResourceRoleImportDto roles)
        => Post<ApiResourceRoleImportDto, OperationStatus>(roles, $"api/apiresourceimport/{apiResource.Id}/roles/validation");

    public Task<ApiCallResult<DataEnvelope<User>>> FindEligibleAssignmentsPaged(DataSourceRequest gridRequest, int envId, SystemPermissionRoleType roleType)
        => Post<DataSourceRequest, DataEnvelope<User>>(gridRequest, $"api/systempermissionroleassignment/datasource?envId={envId}&roleType={roleType}");

    public Task<ApiCallResult<GroupResponse>> SearchGroups(string searchValue, string? skipToken)
        => Get<GroupResponse>($"api/group/search/displayName/{Uri.EscapeDataString(searchValue)}?skipToken={Uri.EscapeDataString(skipToken ?? string.Empty)}");

    public Task<ApiCallResult<UserResponse>> SearchUsers(string searchValue)
    => Get<UserResponse>($"api/user/search/displayName/{Uri.EscapeDataString(searchValue)}");

    public Task<ApiCallResult<UserResponse>> GetUserById(string userId)
        => Get<UserResponse>($"api/user/{userId}");

    public Task<ApiCallResult<Diagnostics>> GetDiagnostics()
        => Get<Diagnostics>("api/diagnostic");

    public Task<ApiCallResult<DataEnvelope<ClientShortDtoRead>>> GetClientsPaged(DataSourceRequest gridRequest)
        => Post<DataSourceRequest, DataEnvelope<ClientShortDtoRead>>(gridRequest, "api/client/datasource");

    public Task<ApiCallResult<DataEnvelope<ClientShortDtoRead>>> GetClientsByScopePaged(string scopeName, DataSourceRequest gridRequest)
        => Post<DataSourceRequest, DataEnvelope<ClientShortDtoRead>>(gridRequest, $"api/client/datasource/scope/{Uri.EscapeDataString(scopeName)}");

    public Task<ApiCallResult<DataEnvelope<ApiResourceShortDtoRead>>> GetApiResourcesPaged(DataSourceRequest gridRequest)
        => Post<DataSourceRequest, DataEnvelope<ApiResourceShortDtoRead>>(gridRequest, "api/apiresource/datasource");

    public Task<ApiCallResult<DataEnvelope<SystemPermissionShortDtoRead>>> GetSystemPermissionsPaged(DataSourceRequest gridRequest)
        => Post<DataSourceRequest, DataEnvelope<SystemPermissionShortDtoRead>>(gridRequest, "api/systempermission/datasource");

    private Task<ApiCallResult<TOut>> Delete<TOut>(string route)
        => SendRequest<TOut>(() => _client.DeleteAsync(route));

    private Task<ApiCallResult<TOut>> Get<TOut>(string route)
        => SendRequest<TOut>(() => _client.GetAsync(route));

    private Task<ApiCallResult<TOut>> Post<TIn, TOut>(TIn obj, string route)
        => SendRequest<TOut>(() => _client.PostAsJsonAsync(route, obj));

    private Task<ApiCallResult<TOut>> Put<TIn, TOut>(TIn obj, string route)
        => SendRequest<TOut>(() => _client.PutAsJsonAsync(route, obj));

    private static async Task<ApiCallResult<TOut>> SendRequest<TOut>(Func<Task<HttpResponseMessage>> request)
    {
        try
        {
            var response = await request();
            return await ProcessResponse<TOut>(response);
        }
        catch (HttpRequestException ex)
        {
            string errorMessage;
            if (ex.Message == "TypeError: Failed to fetch")
            {
                errorMessage = "Failed to connect to the API";
            }
            else
            {
                errorMessage = $"Request has failed";
            }
            if (ex.StatusCode != null)
            {
                errorMessage += $" with HTTP {ex.StatusCode}";
            }
            if (ex.HttpRequestError != HttpRequestError.Unknown)
            {
                errorMessage += $" ({ex.HttpRequestError})";
            }
            return new ApiCallResult<TOut>($"{errorMessage}: {ex.Message} ({ex.GetType().Name})");
        }
        catch (TaskCanceledException)
        {
            return new ApiCallResult<TOut>("Request has timed out");
        }
        catch (Microsoft.AspNetCore.Components.WebAssembly.Authentication.AccessTokenNotAvailableException)
        {
            // this exception is processed by the ErrorBoundary which wraps pages content in MainLayout
            throw;
        }
        catch (Exception ex)
        {
            return new ApiCallResult<TOut>($"Request has failed with an unexpected error: {ex.Message}");
        }
    }

    private static async Task<ApiCallResult<TOut>> ProcessResponse<TOut>(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<TOut>();
            if (EqualityComparer<TOut>.Default.Equals(result, default))
            {
                return new ApiCallResult<TOut>(UnexpectedErrorMessage);
            }
            else
            {
                return new ApiCallResult<TOut>(result!);
            }
        }

        ProblemDetails? problem = null;
        try
        {
            problem = await response.Content.ReadFromJsonAsync<ProblemDetails>();
        }
        catch
        {
            // ignore parsing errors
        }

        return new ApiCallResult<TOut>(
            problem?.ToString() ?? GenericErrorMessage,
            problem?.Extensions != null
                ? problem.Extensions.ToDictionary(kvp => kvp.Key, kvp => kvp.Value?.ToString() ?? string.Empty)
                : null
        );
    }
}
