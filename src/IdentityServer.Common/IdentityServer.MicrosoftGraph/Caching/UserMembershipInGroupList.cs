// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.MicrosoftGraph.Caching;

/// <summary>
/// Wrapper to cache the list of group IDs (value) the specific user ID (key) is a direct or transitive member of.
/// </summary>
public class UserMembershipInGroupList : List<string> { }
