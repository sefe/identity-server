// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web.Models;

public class FeatureOptions
{
    public const string Features = "Features";

    public bool FilterUserRoleOnLogin { get; set; } = false;

    /// <summary>
    /// Max limit of visible resources' writers in the UI on 'Applications' and 'Api Resources' pages.
    /// </summary>
    public int MaxVisibleResourceWriters { get; set; } = 3;
}
