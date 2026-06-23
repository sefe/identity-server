// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.DTO.Import;

public enum ImportStrategy
{
    /// <summary>
    /// Add imported roles to the existing ones.
    /// </summary>
    Add,
    /// <summary>
    /// Replace existing roles with the imported ones.
    /// </summary>
    Replace,
}
