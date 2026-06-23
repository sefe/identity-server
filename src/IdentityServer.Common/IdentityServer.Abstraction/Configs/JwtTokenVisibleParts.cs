// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Configs;

[Flags]
public enum JwtTokenVisibleParts
{
    None = 0,
    Header = 1,
    Payload = 2,
    All = Header | Payload
}
