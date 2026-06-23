// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Contracts;

public interface IHasPeriodData
{
    DateTime ValidFrom { get; set; }
    DateTime ValidTo { get; set; }
}
