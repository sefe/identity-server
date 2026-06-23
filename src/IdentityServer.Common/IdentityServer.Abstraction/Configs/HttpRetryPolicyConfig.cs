// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Configs;

public class HttpRetryPolicyConfig : IHttpRetryPolicyConfig
{
    public int RetryCount { get; set; } = 1;

    public double GrowthFactorInSeconds { get; set; } = 2.0;

    public double DefaultTimeoutInSeconds { get; set; } = 100; // default HttpClient timeout
}
