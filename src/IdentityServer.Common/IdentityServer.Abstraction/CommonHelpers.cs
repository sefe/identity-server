// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Diagnostics;
using System.Reflection;

namespace IdentityServer.Abstraction;

public static class CommonHelpers
{
    public static string? GetEntryAssemblyVersion()
    {
        var attribute = (AssemblyFileVersionAttribute?)Assembly
                .GetEntryAssembly()!
                .GetCustomAttribute(typeof(AssemblyFileVersionAttribute));

        return attribute?.Version;
    }

    public static double GetElapsedMilliseconds(long startTimestamp)
    {
        var elapsed = Stopwatch.GetTimestamp() - startTimestamp;
        return elapsed * 1000.0 / Stopwatch.Frequency;
    }

    public static DateTime GetMaxDateTime(DateTime dt1, DateTime? dt2)
    {
        if (!dt2.HasValue || dt1 >= dt2)
        {
            return dt1;
        }
        else
        {
            return dt2.Value;
        }
    }
}
