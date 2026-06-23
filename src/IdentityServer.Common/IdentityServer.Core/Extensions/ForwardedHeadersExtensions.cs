// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.HttpOverrides;
using System.Diagnostics.CodeAnalysis;
using System.Net;
using IdentityServer.Abstraction.Configs;

namespace IdentityServer.Core.Extensions;

[ExcludeFromCodeCoverage]
public static class ForwardedHeadersExtensions
{
    /// <summary>
    /// Configure Forwarded Headers middleware to replace load balancer IP address with actual remote client IP address if mentioned in the X-Forwarded-For headers.
    /// </summary>
    /// <remarks>Example header value is `X-Forwarded-For: 203.0.113.42, 10.0.0.100`
    /// The first IP(203.0.113.42) is the real client; the next(10.0.0.100) is the proxy.</remarks>
    public static IApplicationBuilder UseLoadBalancerForwardedHeaders(this IApplicationBuilder app, LoadBalancerConfig config)
    {
        var options = new ForwardedHeadersOptions
        {
            ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
            // 10.x.x.x range covers all DV/QA/PP/PR load balancers
            KnownNetworks = { new Microsoft.AspNetCore.HttpOverrides.IPNetwork(IPAddress.Parse(config.IpRange), config.Mask) },
        };

        app.UseForwardedHeaders(options);
        return app;
    }
}
