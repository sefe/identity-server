// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Models;
using Duende.IdentityServer.Stores;
using Duende.IdentityServer.Validation;

namespace IdentityServer.Services.Validation;

/// <summary>
/// This class is called by <seealso cref="IAuthorizeRequestValidator"/> and validates the requested API Resources are enabled.
/// See also <seealso cref="ApiResourceEnabledForEachRequestedScopeValidator"/>.
/// </summary>
public class ApiResourceIsEnabledValidator : DefaultResourceValidator
{
    private readonly IResourceStore _store;
    private readonly ILogger _logger;

    public ApiResourceIsEnabledValidator(IResourceStore store, IScopeParser scopeParser, ILogger<ApiResourceIsEnabledValidator> logger)
        : base(store, scopeParser, logger)
    {
        _store = store;
        _logger = logger;
    }

    protected override async Task ValidateScopeAsync(Client client, Resources resourcesFromStore, ParsedScopeValue requestedScope, ResourceValidationResult result)
    {
        await base.ValidateScopeAsync(client, resourcesFromStore, requestedScope, result);
        if (!result.Succeeded)
        {
            return;
        }

        await ValidateApiResourceIsEnabled(requestedScope.ParsedName, result);
    }

    public async Task ValidateApiResourceIsEnabled(string scopeName, ResourceValidationResult result)
    {
        // Only API Resource scopes are validated by the code. A scope can be OIDC or OAuth2 scope (not validated).
        // API Resource related scope names cannot start with a dot.
        if (!scopeName.Contains('.') || scopeName.StartsWith('.'))
        {
            return;
        }

        var apiName = scopeName.Split('.', 2)[0];
        var storedApis = (await _store.FindApiResourcesByNameAsync(new[] { apiName })).ToList();

        if (storedApis.Count != 1)
        {
            _logger.LogInformation("Expected 1, but found {ApiResourceCount} API Resources found for scope '{ScopeName}'.", storedApis.Count, scopeName);
            result.InvalidScopes.Add(scopeName);
            return;
        }

        var apiResource = storedApis[0];

        if (!apiResource.Enabled)
        {
            _logger.LogInformation("The requested API Resource '{ApiResourceName}' is disabled.", apiResource.Name);
            result.InvalidScopes.Add(scopeName);
        }
    }
}
