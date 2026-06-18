using AutoMapper;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;
using DataEntities = Duende.IdentityServer.EntityFramework.Entities;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <inheritdoc />
internal class ClientPropertyRedirectUriDtoRepository :
    ClientCacheablePropertyBaseDtoRepository<ClientPropertyRedirectUriDtoRead, ClientPropertyRedirectUriDtoCreate, ClientRedirectUriExt>
{
    private readonly ILogger<ClientPropertyRedirectUriDtoRepository> _logger;

    public ClientPropertyRedirectUriDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ClientRedirectUriExt> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<ClientRedirectUriExt, ClientExt> parentAccessor,
        ICache<DataEntities.Client> clientCache,
        ILogger<ClientPropertyRedirectUriDtoRepository> logger
        ) : base(clientStorage, propertyStorage, mapper, permissionChecker, parentAccessor, clientCache)
    {
        _logger = logger ?? NullLogger<ClientPropertyRedirectUriDtoRepository>.Instance;
    }

    protected override int GetParentId(ClientPropertyRedirectUriDtoCreate createDto) => createDto.ClientId;

    protected override async Task ThrowIfExistsOrInvalid(ClientPropertyRedirectUriDtoCreate createDto)
    {
        var existingResources = await _propertyStorage.ToListAsync(x => x.ClientId == createDto.ClientId) ?? Enumerable.Empty<ClientRedirectUriExt>();
        var sameUri = existingResources.FirstOrDefault(x => string.Equals(x.RedirectUri, createDto.RedirectUri, StringComparison.OrdinalIgnoreCase));
        if (sameUri != null)
        {
            throw new EntityAlreadyExistsException($"Application '{sameUri.ClientId}' already contains Redirect URI '{sameUri.RedirectUri}'.");
        }
    }

    protected override Task OnBeforeCreateAsync(ClaimsPrincipal user, ClientExt parent, ClientRedirectUriExt propertyToCreate)
    {
        if (!Uri.TryCreate(propertyToCreate.RedirectUri, UriKind.Absolute, out var uri))
        {
            throw new ArgumentException("Redirect URI must be an absolute URI.");
        }

        if (uri.Scheme == Uri.UriSchemeHttp && !uri.IsLoopbackUri())
        {
            _logger.LogWarning("Insecure HTTP Redirect URI is added to {ClientId}: {RequestedRedirectUri}", parent.ClientId, propertyToCreate.RedirectUri);
        }

        return Task.CompletedTask;
    }
}
