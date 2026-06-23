// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Runtime.Serialization;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Web.Models.Validation;

[UniquePropertyValue(nameof(Origin), "CORS Origin")]
public class ClientPropertyCorsOriginDtoCreateWrapper : ClientPropertyCorsOriginDtoCreate, IHasUniquePropertyValue
{
    [IgnoreDataMember]
    public HashSet<string> AlreadyExistingUniquePropertyValues { get; set; } = new();

    [IgnoreDataMember]
    public string UniqueProperty => Origin;
}
