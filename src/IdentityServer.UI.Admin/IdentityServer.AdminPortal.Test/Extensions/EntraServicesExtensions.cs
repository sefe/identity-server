// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using NSubstitute;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.AdminPortal.Test.Extensions;

internal static class EntraServicesExtensions
{
    public static (string oid, string name) SetupUserResponse(this IEntraUserService entraUserService)
    {
        var userObjectId = Guid.NewGuid().ToString();
        const string userDisplayName = "Test User";
        entraUserService.GetUserByObjectIdAsync(Arg.Any<string>()).Returns(new UserResponse { Users = new() { new User { OId = userObjectId, DisplayName = userDisplayName, AccountEnabled = true } } });

        return (userObjectId, userDisplayName);
    }

    public static (string oid, string name) SetupSecurityGroupResponse(this IEntraGroupService entraGroupService)
    {
        var groupObjectId = Guid.NewGuid().ToString();
        var name = "SecurityGroupDisplayName";
        entraGroupService.GetGroupByObjectIdAsync(Arg.Any<string>()).Returns(new GroupResponse { Groups = new() { new Group { Id = groupObjectId, DisplayName = name } } });

        return (groupObjectId, name);
    }
}
