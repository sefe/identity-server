// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web.Models.Validation;

public interface IHasUniquePropertyValue
{
    string UniqueProperty { get; }
    HashSet<string> AlreadyExistingUniquePropertyValues { get; }
}
