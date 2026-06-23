// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using AutoFixture;
using AutoFixture.AutoNSubstitute;
using NSubstitute;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Data.Test;

public abstract class TestBase<T>
{
    protected virtual void CustomiseAutoFixture(Fixture fixture)
    {
    }

    protected Fixture Fixture;
    protected T SystemUnderTest;
    protected Exception RecordedException;
    bool _recordExceptions;
    protected ClaimsPrincipal User;
    protected IPermissionChecker EverythingIsAllowed;

    [OneTimeSetUp]
    public void Setup()
    {
        User = CreateClaimsPrincipal("007", RoleNames.Reader, RoleNames.User, RoleNames.Admin);
        EverythingIsAllowed = Substitute.For<IPermissionChecker>();
        EverythingIsAllowed.GetAccessRoleOrThrowIfNoAccessToEnvAsync(Arg.Any<ClaimsPrincipal>(), Arg.Any<int>(), Arg.Any<EntityAccessType>(), Arg.Any<string>()).Returns(SystemPermissionRoleType.Writer);
        EverythingIsAllowed.GetAllAccessiblePermissionEnvironmentsAsync(User, Arg.Any<SystemPermissionRoleType>()).Returns(new HashSet<int>(Enumerable.Range(0, 99)));
        Fixture = new Fixture();
        // enable auto mocking with NSubstitute - fixture now  auto-mocking container 
        Fixture.Customize(new AutoNSubstituteCustomization { ConfigureMembers = true });
        CustomiseAutoFixture(Fixture);
        Given();

        try
        {
            SystemUnderTest = CreateSystemUnderTest();
            When();
        }
        catch (Exception ex)
        {
            if (_recordExceptions)
            {
                RecordedException = ex;
            }
            else
            {
                throw;
            }
        }
    }

    protected virtual void Given()
    {
    }

    protected virtual void When()
    {
    }

    protected virtual T CreateSystemUnderTest()
    {
        return Fixture.Create<T>();
    }

    protected void RecordExceptions()
    {
        _recordExceptions = true;
    }

    protected static ClaimsPrincipal CreateClaimsPrincipal(string userObjectId, params string[] roles)
    {
        var claims = new List<Claim>() {
            new("oid", userObjectId)
        };

        foreach (var role in roles)
        {
            claims.Add(new Claim("role", role));
        }

        var identity = new ClaimsIdentity(claims, "TestAuthType", "oid", "role");
        var claimsPrincipal = new ClaimsPrincipal(identity);
        return claimsPrincipal;
    }
}
