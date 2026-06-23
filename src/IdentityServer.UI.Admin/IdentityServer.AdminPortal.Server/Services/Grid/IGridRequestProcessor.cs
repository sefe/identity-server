// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Telerik.DataSource;

namespace IdentityServer.AdminPortal.Server.Services.Grid;

public interface IGridRequestProcessor
{
    Task ProcessGridRequestAsync(DataSourceRequest request);
}

