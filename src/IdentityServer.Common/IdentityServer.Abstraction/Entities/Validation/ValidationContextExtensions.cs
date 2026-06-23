// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.Entities.Validation;

public static class ValidationContextExtensions
{
    public static IEnumerable<string> GetMemberNames(this ValidationContext validationContext)
    {
        return validationContext?.MemberName != null
            ? new[] { validationContext.MemberName }
            : Array.Empty<string>();
    }
}
