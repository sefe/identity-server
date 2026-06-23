// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.ApiResources;

namespace IdentityServer.Data.Services;

public interface IReportingService
{
    Task<ApiRolesAssignmentsDto> BuildReportAsync(ApiRolesReportRequest request);
}
