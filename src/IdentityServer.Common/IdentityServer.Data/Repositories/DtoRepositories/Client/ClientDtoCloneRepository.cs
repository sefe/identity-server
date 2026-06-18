using AutoMapper;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Abstraction.Extensions;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Repositories.DtoRepositories.Client;

/// <summary>
/// Responsible for DTO cloning and access security checks for <seealso cref="ClientExt"/> entities.
/// </summary>
internal class ClientDtoCloneRepository :
    IDtoCloneRepository<ClientDtoRead, ClientDtoClone>
{
    private readonly IStorage<ClientExt> _clientStorage;
    private readonly IStorage<SystemPermissionEnvironment> _sysEnvStorage;
    private readonly IMapper _mapper;
    private readonly IPermissionChecker _permissionChecker;

    public ClientDtoCloneRepository(
        IStorage<ClientExt> clientStorage,
        IStorage<SystemPermissionEnvironment> sysEnvStorage,
        IMapper mapper,
        IPermissionChecker permissionChecker)
    {
        _clientStorage = clientStorage;
        _sysEnvStorage = sysEnvStorage;
        _mapper = mapper;
        _permissionChecker = permissionChecker;
    }

    public async Task<ClientDtoRead> CloneAsync(ClaimsPrincipal user, ClientDtoClone resource)
    {
        var roleInTarget = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, resource.SystemPermissionEnvironmentId, EntityAccessType.Create, "Application");

        var entity = await _clientStorage.GetByIdAsync(resource.Id) ?? throw new EntityNotFoundException($"Application with Id {resource.Id} was not found.");
        _ = await _permissionChecker.GetAccessRoleOrThrowIfNoAccessToEnvAsync(user, entity.SystemPermissionEnvironmentId, EntityAccessType.Read, entity.ToString()!);

        var existingResource = await _clientStorage.FirstOrDefaultAsync(x => x.ClientId == resource.ClientId);
        if (existingResource != null)
        {
            throw new EntityAlreadyExistsException($"Application with id '{existingResource.ClientId}' already exists.");
        }

        var env = await _sysEnvStorage.GetByIdAsync(resource.SystemPermissionEnvironmentId)
            ?? throw new EntityNotFoundException($"System Permission Environment with Id {resource.SystemPermissionEnvironmentId} was not found.");

        var clonedEntity = CreateClientCopy(entity, env);
        clonedEntity.ClientId = resource.ClientId;
        clonedEntity.ClientName = resource.ClientName;

        var storedClient = await _clientStorage.AddAsync(clonedEntity);
        var result = _mapper.Map<ClientDtoRead>(storedClient);
        result.AccessLevel = roleInTarget;
        return result;
    }

    internal static ClientExt CreateClientCopy(ClientExt source, SystemPermissionEnvironment env)
    {
        var copy = new ClientExt()
        {
            Id = 0,
            Created = DateTime.UtcNow,

            Description = source.Description,
            Enabled = source.Enabled,
            RequireClientSecret = source.RequireClientSecret,
            RequirePkce = source.RequirePkce,
            AccessTokenType = source.AccessTokenType,
            AllowOfflineAccess = source.AllowOfflineAccess,

            SystemPermissionEnvironment = env,
            SystemPermissionEnvironmentId = env.Id,
        };
        // Skip CORS origins because environmental data
        // Skip secrets
        // Skip EntraID Apps

        // Copy all Grant Types
        CopyGrantTypes(source, copy);

        // Copy non-environment-specific Redirect and Post-Logout Redirect URIs
        CopyRedirectUris(source, copy);

        // Copy OIDC scopes only
        CopyOidcScopes(source, copy);

        // Copy roles without mappings
        CopyRoles(source, copy);

        return copy;
    }

    internal static void CopyOidcScopes(ClientExt source, ClientExt copy)
    {
        if (source.AllowedScopes != null)
        {
            copy.AllowedScopes = new();
            foreach (var scope in source.AllowedScopes.Where(s => OidcScopeNames.OidcStandardScopeIds.Contains(s.Scope)))
            {
                copy.AllowedScopes.Add(new ClientScopeExt
                {
                    Id = 0,
                    ClientId = 0,
                    Scope = scope.Scope
                });
            }
        }
    }

    internal static void CopyRedirectUris(ClientExt source, ClientExt copy)
    {
        if (source.RedirectUris != null)
        {
            copy.RedirectUris = new();
            foreach (var redirect in source.RedirectUris.Where(ru => IsLocalHostUri(ru.RedirectUri)))
            {
                copy.RedirectUris.Add(new ClientRedirectUriExt { Id = 0, ClientId = 0, RedirectUri = redirect.RedirectUri });
            }
        }

        if (source.PostLogoutRedirectUris != null)
        {
            copy.PostLogoutRedirectUris = new();
            foreach (var redirect in source.PostLogoutRedirectUris.Where(ru => IsLocalHostUri(ru.PostLogoutRedirectUri)))
            {
                copy.PostLogoutRedirectUris.Add(new ClientPostLogoutRedirectUriExt { Id = 0, ClientId = 0, PostLogoutRedirectUri = redirect.PostLogoutRedirectUri });
            }
        }
    }

    internal static void CopyGrantTypes(ClientExt source, ClientExt copy)
    {
        if (source.AllowedGrantTypes != null)
        {
            copy.AllowedGrantTypes = new();
            foreach (var grant in source.AllowedGrantTypes)
            {
                copy.AllowedGrantTypes.Add(new ClientGrantTypeExt
                {
                    Id = 0,
                    GrantType = grant.GrantType,
                    ClientId = 0
                });
            }
        }
    }

    internal static void CopyRoles(ClientExt source, ClientExt target)
    {
        target.Roles = source.Roles.Select(_ => new Entities.Roles.ClientRole() { RoleName = _.RoleName }).ToList();
    }

    internal static bool IsLocalHostUri(string redirectUri)
    {
        return !string.IsNullOrEmpty(redirectUri) && Uri.TryCreate(redirectUri, UriKind.Absolute, out var uri) && uri.IsLoopbackUri();
    }
}
