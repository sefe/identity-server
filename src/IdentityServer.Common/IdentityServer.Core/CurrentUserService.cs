using Microsoft.AspNetCore.Http;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Core;

public class CurrentUserService : ICurrentUserService
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public CurrentUserService(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public string? UserName => _httpContextAccessor.HttpContext?.User.GetUserNameOrDefault();
}

