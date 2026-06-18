using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Tests.Common;

namespace IdentityServer.AdminPortal.Test.Controller;

public abstract class ControllerTestBase
{
    protected static ClaimsPrincipal SuperUser => TestUser.SuperUser;
    protected static ClaimsPrincipal Reader => TestUser.Reader;
    protected static ClaimsPrincipal Contributor => TestUser.Contributor;
    protected static ClaimsPrincipal Contributor2 => TestUser.Contributor2;
    protected static ClaimsPrincipal Admin => TestUser.Admin;

    protected readonly IPermissionChecker EverythingIsAllowed;

    protected IStorage<SystemPermission> SystemPermissionStorage;
    protected IStorage<SystemPermissionEnvironment> SystemPermissionEnvStorage;

    protected ControllerTestBase()
    {
        EverythingIsAllowed = Substitute.For<IPermissionChecker>();
        EverythingIsAllowed.GetAccessRoleOrThrowIfNoAccessToEnvAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<int>(), Arg.Any<EntityAccessType>(), Arg.Any<string>()).Returns(SystemPermissionRoleType.Writer);
        EverythingIsAllowed.GetAllAccessiblePermissionEnvironmentsAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<SystemPermissionRoleType>()).Returns(new HashSet<int>(Enumerable.Range(0, 99)));
    }

    protected static void SetControllerContext(ControllerBase controller)
    {
        SetControllerContext(controller, TestUser.Reader);
    }

    public static void SetControllerContext(ControllerBase controller, ClaimsPrincipal claimsPrincipal)
    {
        var httpContext = Substitute.For<HttpContext>();
        httpContext.User.Returns(claimsPrincipal);

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = httpContext
        };
    }

    public async Task Setup(IServiceProvider provider)
    {
        SystemPermissionStorage = provider.GetRequiredService<IStorage<SystemPermission>>();
        SystemPermissionEnvStorage = provider.GetRequiredService<IStorage<SystemPermissionEnvironment>>();

        var sp = await SystemPermissionStorage.AddAsync(new SystemPermission { Name = "1", Description = "Description 1" });
        await SystemPermissionEnvStorage.AddAsync(new SystemPermissionEnvironment { SystemPermission = sp, Environment = SystemPermissionEnvironmentNames.Development });
    }
}
