// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Entities;

public class DiagnosticMetrics
{
    public int DailyAverageErrors { get; set; }
    public int TotalErrorsLastHour { get; set; }
    public int TotalErrorsLastDay { get; set; }
    public int MetricUpperBound { get; set; }
}