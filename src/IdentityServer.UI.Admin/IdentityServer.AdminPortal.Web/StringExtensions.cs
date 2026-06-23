// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web
{
    public static class StringExtensions
    {
        public static bool Match(this string? input, string compare, StringComparison comparision = StringComparison.OrdinalIgnoreCase)
            => String.Equals(input, compare, comparision);
    }
}
