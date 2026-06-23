// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Options;
using IdentityServer.AdminPortal.Web.Models;
using IdentityServer.AdminPortal.Web.Services.Storage;

namespace IdentityServer.AdminPortal.Web.Services;

public class UserRoleFilteringService
{
    public static List<string> AllRoles => new() { Abstraction.Constants.RoleNames.Admin, Abstraction.Constants.RoleNames.User, Abstraction.Constants.RoleNames.Reader };

    private const string _storageKey = "userRoleFilter";

    private readonly SessionStorageService _storage;
    private readonly IOptions<FeatureOptions> _features;

    public UserRoleFilteringService(SessionStorageService storage, IOptions<FeatureOptions> features)
    {
        _storage = storage;
        _features = features;
    }

    public ValueTask SetAllowedRoles(List<string> allowedRoles)
    {
        if (_features.Value.FilterUserRoleOnLogin)
        {
            return _storage.SetItem(_storageKey, allowedRoles);
        }

        return ValueTask.CompletedTask;
    }

    public async Task<List<string>> GetAllowedRoles()
    {
        if (_features.Value.FilterUserRoleOnLogin)
        {
            var savedRoles = await _storage.GetItem<List<string>>(_storageKey);
            return savedRoles ?? AllRoles;
        }

        return AllRoles;
    }
}
