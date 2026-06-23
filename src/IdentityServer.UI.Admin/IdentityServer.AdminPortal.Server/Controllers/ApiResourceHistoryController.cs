// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Mvc;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.AdminPortal.Server.Controllers;

/// <summary>
/// Controller for retrieving API resource change history.
/// </summary>
[Route("api/apiresources")]
public class ApiResourceHistoryController : HistoryControllerBase
{
    public ApiResourceHistoryController(IApiResourceHistoryRepository historyRepository)
        : base(historyRepository)
    {
    }
}
