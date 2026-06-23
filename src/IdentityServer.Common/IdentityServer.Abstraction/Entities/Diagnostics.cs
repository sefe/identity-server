// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Entities;

public class Diagnostics
{
    public required ICollection<LogDocument> Logs { get; set; }
    public required DiagnosticMetrics Metrics { get; set; }
}