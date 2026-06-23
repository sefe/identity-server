// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive.Banner;

public class TestSecret : IHasExpiration
{
    public DateTime? Expiration { get; set; }
}
