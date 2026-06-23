// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.Entities;

namespace IdentityServer.AdminPortal.Web.Services.Search;

public interface ISearchProvider<T>
{
    Task<SearchResult2<T>> SearchAsync(string input, string? skipToken);
}
