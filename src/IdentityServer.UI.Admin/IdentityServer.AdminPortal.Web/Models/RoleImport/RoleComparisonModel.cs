// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web.Models.RoleImport;

public class RoleComparisonModel
{
    public required string RoleName { get; set; }
    public ComparisonState RoleState { get; set; } = ComparisonState.Unchanged;
    public ComparisonState? RoleMappingState
    {
        get
        {
            if (Mappings == null || Mappings.Count == 0)
            {
                return null;
            }

            var states = Mappings.Select(m => m.State).ToHashSet();
            if (states.Count == 1)
            {
                return states.First();
            }
            else
            {
                return ComparisonState.Mixed;
            }
        }
    }
    public List<RoleMappingComparisonModel> Mappings { get; set; } = new();
}
