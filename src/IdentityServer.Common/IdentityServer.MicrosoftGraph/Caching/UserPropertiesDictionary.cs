// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.MicrosoftGraph.Caching;

/// <summary>
/// Wrapper to cache the user profile properties (value) of the specific user ID (key).
/// </summary>
public class UserPropertiesDictionary : Dictionary<string, string>
{
    public UserPropertiesDictionary()
    {
    }

    public UserPropertiesDictionary(IDictionary<string, string> dictionary) : base(dictionary)
    {
    }
}
