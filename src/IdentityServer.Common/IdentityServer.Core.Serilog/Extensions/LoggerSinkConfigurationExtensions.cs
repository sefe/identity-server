// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Serilog;
using Serilog.Configuration;
using Serilog.Sinks.Http.BatchFormatters;
using Serilog.Sinks.Http.HttpClients;
using Serilog.Sinks.Http.Private.Durable;
using System.IO.Compression;
using System.Net.Http.Headers;
using System.Text;

namespace IdentityServer.Core.Serilog.Extensions;

public static class LoggerSinkConfigurationExtensions
{
    public static LoggerConfiguration TradingStandardSink(this LoggerSinkConfiguration sinkConfiguration, TradingSinkConfig sinkConfig)
    {
        ArgumentNullException.ThrowIfNull(sinkConfiguration);

        var period = sinkConfig.Period ?? TimeSpan.FromSeconds(2.0);
        JsonGzipHttpClient httpClient = new(CreateHttpClient(sinkConfig.Username, sinkConfig.Password), CompressionLevel.Fastest);
        TradingTextFormatter textFormatter = new(sinkConfig.ApplicationName);
        ArrayBatchFormatter batchFormatter = new();
        FileSizeRolledDurableHttpSink logEventSink = new(
            sinkConfig.RequestUri,
            sinkConfig.BufferBaseFileName,
            sinkConfig.BufferFileSizeLimitBytes,
            sinkConfig.BufferFileShared,
            sinkConfig.RetainedBufferFileCountLimit,
            sinkConfig.LogEventLimitBytes,
            sinkConfig.LogEventsInBatchLimit,
            sinkConfig.BatchSizeLimitBytes,
            period,
            textFormatter,
            batchFormatter,
            httpClient
        );
        return sinkConfiguration.Sink(logEventSink, sinkConfig.RestrictedToMinimumLevel);
    }

    private static HttpClient CreateHttpClient(string username, string password)
    {
        HttpClient httpClient = new();
        byte[] bytes = Encoding.ASCII.GetBytes(username + ":" + password);
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(bytes));
        return httpClient;
    }
}
