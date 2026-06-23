// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Runtime.Serialization;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Web.Models.Validation;

[UniquePropertyValue(nameof(PostLogoutRedirectUri), "Post-Logout Redirect URI")]
public class ClientPropertyPostLogoutRedirectUriDtoCreateWrapper : ClientPropertyPostLogoutRedirectUriDtoCreate, IHasUniquePropertyValue
{
    [IgnoreDataMember]
    public HashSet<string> AlreadyExistingUniquePropertyValues { get; set; } = new();

    [IgnoreDataMember]
    public string UniqueProperty => PostLogoutRedirectUri;
}
