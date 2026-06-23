// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;

namespace IdentityServer.Data.Security;

public class UserGroupMembershipService : IUserGroupMembershipService
{
    private readonly IEntraUserService _entraUserService;
    private readonly IAuthConfig _authConfig;

    public UserGroupMembershipService(IEntraUserService entraUserService, IAuthConfig authConfig)
    {
        _entraUserService = entraUserService;
        _authConfig = authConfig;

        if (string.IsNullOrEmpty(_authConfig.ReaderGroupId))
        {
            throw new InvalidOperationException("Readers Group not configured.");
        }

        if (string.IsNullOrEmpty(_authConfig.ContributorGroupId))
        {
            throw new InvalidOperationException("Contributors Group not configured.");
        }
    }
    public Task<bool> IsContributorAsync(string userObjectId)
    {
        return UserHasAnyGroup(userObjectId, new[] { _authConfig.ContributorGroupId });
    }

    public Task<bool> IsReaderOrContributorAsync(string userObjectId)
    {
        return UserHasAnyGroup(userObjectId, new[] { _authConfig.ReaderGroupId, _authConfig.ContributorGroupId });
    }

    private async Task<bool> UserHasAnyGroup(string userObjectId, IEnumerable<string> expectedGroupIds)
    {
        var userGroups = await _entraUserService.GetUserMembershipInGroups(userObjectId, expectedGroupIds);
        return userGroups != null && userGroups.Any(g => expectedGroupIds.Contains(g.Id, StringComparer.OrdinalIgnoreCase));
    }
}
