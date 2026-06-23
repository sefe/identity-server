// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Contracts;

public interface IHasCreatedInfo
{
    DateTime? Created { get; set; }
    public string? CreatedBy { get; set; }
}
