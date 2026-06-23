// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientDtoSearchResponse
{
    public required string ClientId { get; set; }
    public required string ClientName { get; set; }
}
