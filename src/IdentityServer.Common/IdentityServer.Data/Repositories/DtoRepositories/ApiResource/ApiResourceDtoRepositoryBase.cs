// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using AutoMapper;
using Microsoft.Extensions.Logging;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.DTO.ApiResources;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.DtoRepositories.ApiResource;

/// <summary>
/// Group common reusable methods for API Resource DTO repositories.
/// </summary>
internal abstract class ApiResourceDtoRepositoryBase
{
    protected readonly IStorage<ApiResourceExt> _apiResourceStorage;
    protected readonly IPermissionChecker _permissionChecker;
    protected readonly IStorage<ApiScopeExt> _apiScopeStorage;
    protected readonly IStorage<ClientScopeExt> _clientScopeStorage;
    protected readonly IMapper _mapper;
    protected readonly ILogger _logger;

    protected ApiResourceDtoRepositoryBase(
        IStorage<ApiResourceExt> apiResourceStorage,
        IStorage<ApiScopeExt> apiScopeStorage,
        IStorage<ClientScopeExt> clientScopeStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        ILogger logger)
    {
        _apiResourceStorage = apiResourceStorage;
        _apiScopeStorage = apiScopeStorage;
        _clientScopeStorage = clientScopeStorage;
        _mapper = mapper;
        _permissionChecker = permissionChecker;
        _logger = logger;
    }

    protected async Task PopulateApiScopesAsync(List<ApiResourcePropertyScopeDtoRead> apiResourceScopes)
    {
        // ApiResource Scopes have only Name field populated. The rest must be loaded from ApiScopes.
        var apiScopeNames = apiResourceScopes.Select(a => a.Scope).ToHashSet(StringComparer.Ordinal);
        if (apiScopeNames.Count != 0)
        {
            var dbScopes = (await _apiScopeStorage.ToListAsync(s => apiScopeNames.Contains(s.Name))).ToDictionary(s => s.Name, StringComparer.Ordinal);

            // Fetch client counts for each scope
            var clientScopes = await _clientScopeStorage.ToListAsync(cs => apiScopeNames.Contains(cs.Scope));
            var clientCounts = clientScopes
                .GroupBy(cs => cs.Scope)
                .ToDictionary(g => g.Key, g => g.Select(cs => cs.ClientId).Distinct().Count(), StringComparer.Ordinal);

            foreach (var apiResourceScope in apiResourceScopes)
            {
                if (dbScopes.TryGetValue(apiResourceScope.Scope, out var apiScope))
                {
                    var scopeDto = _mapper.Map<ApiScopeDtoRead>(apiScope);
                    scopeDto.ClientCount = clientCounts.TryGetValue(apiResourceScope.Scope, out var count) ? count : 0;
                    apiResourceScope.ApiScope = scopeDto;
                }
            }
        }
    }
}
