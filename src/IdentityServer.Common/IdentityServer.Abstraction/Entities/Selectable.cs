// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Entities;

public class Selectable
{
    public bool IsSelected { get; set; }
    public required string DisplayName { get; set; }
}

public class SelectableValue<T> : Selectable
{
    public required T Value { get; set; }
}
