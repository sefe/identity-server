// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace IdentityServer.AdminPortal.Server.Infrastructure;

public static class TrimModelBinderRecursionGuard
{
    public static readonly AsyncLocal<bool> IsActive = new();
}

public class TrimModelBinderProvider : IModelBinderProvider
{
    public IModelBinder? GetBinder(ModelBinderProviderContext context)
    {
        if (TrimModelBinderRecursionGuard.IsActive.Value)
        {
            return null;
        }

        // Only apply to top-level body-bound models (DTOs from [FromBody])
        if (context.BindingInfo.BindingSource != null &&
            context.BindingInfo.BindingSource.CanAcceptDataFrom(BindingSource.Body) &&
            context.Metadata.IsComplexType &&
            context.Metadata.ModelType != typeof(string))
        {
            TrimModelBinderRecursionGuard.IsActive.Value = true;

            try
            {
                var fallbackBinder = context.CreateBinder(context.Metadata);
                return new TrimModelBinder(fallbackBinder);
            }
            finally
            {
                TrimModelBinderRecursionGuard.IsActive.Value = false;
            }
        }

        return null;
    }
}
