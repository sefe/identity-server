// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web.Models.RoleImport;

public enum ComparisonState
{
    Unchanged,
    Added,
    Removed,
    Changed,
    Conflict,
    Mixed,
}
