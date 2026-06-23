// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.AdminPortal.Server.Infrastructure;

public class RequestBodyLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly HashSet<string> _httpMethodsToLog = new() { HttpMethods.Post, HttpMethods.Put, HttpMethods.Patch, HttpMethods.Delete };

    public RequestBodyLoggingMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task Invoke(HttpContext context)
    {
        if (_httpMethodsToLog.Contains(context.Request.Method))
        {
            await AddRequestBodyToTelemetry(context);
        }

        await _next(context);
    }

    private static async Task AddRequestBodyToTelemetry(HttpContext context)
    {
        try
        {
            context.Request.EnableBuffering();

            using var reader = new StreamReader(context.Request.Body, Encoding.UTF8,
                detectEncodingFromByteOrderMarks: false,
                bufferSize: 512, leaveOpen: true);

            var payload = await reader.ReadToEndAsync();
            context.Items[CustomContextFields.RequestBody] = payload;
        }
        catch { /* ignore exceptions */ }
        finally
        {
            TryResetRequestBodyStreamPosition(context.Request.Body);
        }
    }

    private static void TryResetRequestBodyStreamPosition(Stream body)
    {
        try
        {
            if (body.Position != 0)
            {
                body.Position = 0;
            }
        }
        catch { /* ignore exceptions */ }
    }
}
