// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Contracts.MicrosoftGraph;

public interface IUserGroupMembershipService
{
    Task<bool> IsReaderOrContributorAsync(string userObjectId);

    Task<bool> IsContributorAsync(string userObjectId);
}