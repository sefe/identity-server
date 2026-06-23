// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Core.Serilog.Entities;
public class ContextDataProperty<T>
{
    public required string Name { get; set; }

    public T? Value { get; set; }
}
