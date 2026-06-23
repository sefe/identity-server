// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using AutoMapper;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <inheritdoc />
internal class ClientPropertyPostLogoutRedirectUriDtoRepository :
    ClientCacheablePropertyBaseDtoRepository<ClientPropertyPostLogoutRedirectUriDtoRead, ClientPropertyPostLogoutRedirectUriDtoCreate, ClientPostLogoutRedirectUriExt>
{
    private readonly ILogger<ClientPropertyPostLogoutRedirectUriDtoRepository> _logger;

    public ClientPropertyPostLogoutRedirectUriDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ClientPostLogoutRedirectUriExt> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<ClientPostLogoutRedirectUriExt, ClientExt> parentAccessor,
        ICache<DataEntities.Client> clientCache,
        ILogger<ClientPropertyPostLogoutRedirectUriDtoRepository> logger
        ) : base(clientStorage, propertyStorage, mapper, permissionChecker, parentAccessor, clientCache)
    {
        _logger = logger ?? NullLogger<ClientPropertyPostLogoutRedirectUriDtoRepository>.Instance;
    }

    protected override int GetParentId(ClientPropertyPostLogoutRedirectUriDtoCreate createDto) => createDto.ClientId;

    protected override async Task ThrowIfExistsOrInvalid(ClientPropertyPostLogoutRedirectUriDtoCreate createDto)
    {
        var existingResources = await _propertyStorage.ToListAsync(x => x.ClientId == createDto.ClientId) ?? Enumerable.Empty<ClientPostLogoutRedirectUriExt>();
        var sameUri = existingResources.FirstOrDefault(x => string.Equals(x.PostLogoutRedirectUri, createDto.PostLogoutRedirectUri, StringComparison.OrdinalIgnoreCase));
        if (sameUri != null)
        {
            throw new EntityAlreadyExistsException($"Application '{sameUri.ClientId}' already contains Post-Logout Redirect URI '{sameUri.PostLogoutRedirectUri}'.");
        }
    }

    protected override Task OnBeforeCreateAsync(ClaimsPrincipal user, ClientExt parent, ClientPostLogoutRedirectUriExt propertyToCreate)
    {
        if (!Uri.TryCreate(propertyToCreate.PostLogoutRedirectUri, UriKind.Absolute, out var uri))
        {
            throw new ArgumentException("Post-Logout Redirect URI must be an absolute URI.");
        }

        if (uri.Scheme == Uri.UriSchemeHttp && !uri.IsLoopbackUri())
        {
            _logger.LogWarning("Insecure HTTP Post-Logout Redirect URI is added to {ClientId}: {RequestedPostLogoutRedirectUri}", parent.ClientId, propertyToCreate.PostLogoutRedirectUri);
        }

        return Task.CompletedTask;
    }
}
