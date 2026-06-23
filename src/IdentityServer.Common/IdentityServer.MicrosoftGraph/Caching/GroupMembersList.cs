// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.MicrosoftGraph.Caching;

/// <summary>
/// Wrapper to cache the list of user IDs (value) of a specific group ID (key).
/// </summary>
public class GroupMembersList : List<string>
{
    public GroupMembersList()
    {
    }

    public GroupMembersList(IEnumerable<string> collection) : base(collection)
    {
    }
}
