// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Configs;

public interface IAuthConfig
{
    string ContributorGroupId { get; }

    string ReaderGroupId { get; }
}