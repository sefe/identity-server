using AutoMapper;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.Storage;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <inheritdoc />
internal class ClientPropertyEntraAppDtoRepository :
    ClientPropertyBaseDtoRepository<ClientPropertyEntraAppDtoRead, ClientPropertyEntraAppDtoCreate, ClientEntraApp>
{
    private readonly IEntraApplicationService _entraAppService;

    public ClientPropertyEntraAppDtoRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<ClientEntraApp> propertyStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker,
        IParentAccessor<ClientEntraApp, ClientExt> parentAccessor,
        IEntraApplicationService entraAppService
        ) : base(clientStorage, propertyStorage, mapper, permissionChecker, parentAccessor)
    {
        _entraAppService = entraAppService;
    }

    protected override int GetParentId(ClientPropertyEntraAppDtoCreate createDto) => createDto.ClientId;

    protected override async Task ThrowIfExistsOrInvalid(ClientPropertyEntraAppDtoCreate createDto)
    {
        var existingResources = await _propertyStorage.ToListAsync(x => x.ClientId == createDto.ClientId);
        var existingResource = existingResources?.FirstOrDefault(x => x.AppId.IsSameLax(createDto.AppId));
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"Application '{existingResource.ClientId}' already contains mapped EntraID App '{existingResource.AppId}'.");
        }
    }

    protected override async Task OnBeforeCreateAsync(ClaimsPrincipal user, ClientExt parent, ClientEntraApp propertyToCreate)
    {
        var entraApp = await _entraAppService.GetByIdAsync(propertyToCreate.AppId) ??
            throw new EntityNotFoundException($"Application ID '{propertyToCreate.AppId}' wasn't found in EntraID.");
        propertyToCreate.AppName = entraApp.DisplayName;
    }
}
