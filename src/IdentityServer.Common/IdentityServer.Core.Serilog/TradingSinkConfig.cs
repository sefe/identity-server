// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Serilog.Events;

namespace IdentityServer.Core.Serilog;

public class TradingSinkConfig
{
    public required string RequestUri { get; set; }

    public required string Username { get; set; }

    public required string Password { get; set; }

    public required string ApplicationName { get; set; }

    public string BufferBaseFileName { get; set; } = "Buffer";

    public long? BufferFileSizeLimitBytes { get; set; } = 1073741824L;

    public bool BufferFileShared { get; set; }

    public int? RetainedBufferFileCountLimit { get; set; } = 31;

    public long? BatchSizeLimitBytes { get; set; }

    public int? LogEventsInBatchLimit { get; set; } = 1000;

    public long? LogEventLimitBytes { get; set; }

    public TimeSpan? Period { get; set; }

    public LogEventLevel RestrictedToMinimumLevel { get; set; }
}
