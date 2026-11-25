// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.OpenApi;
using Swashbuckle.AspNetCore.Swagger;

namespace IdentityServer.Test;

[TestFixture]
public class HostingExtensionsTests
{
    [Test]
    public void AddSwagger_ShouldRequireBearerAuthentication()
    {
        var builder = WebApplication.CreateBuilder();
        builder.Services.AddControllers().AddApplicationPart(typeof(HostingExtensions).Assembly);
        builder.AddSwagger();
        using var services = builder.Services.BuildServiceProvider();

        var document = services.GetRequiredService<ISwaggerProvider>().GetSwagger("v1");

        Assert.That(document.Security, Has.Count.EqualTo(1));
        Assert.That(document.Paths, Is.Not.Empty);
        var requirement = document.Security.Single();
        Assert.That(requirement, Has.Count.EqualTo(1));
        var scheme = requirement.Keys.Single();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(scheme.Reference.Id, Is.EqualTo("Bearer"));
            Assert.That(scheme.Type, Is.EqualTo(SecuritySchemeType.Http));
            Assert.That(scheme.Scheme, Is.EqualTo("bearer"));
            Assert.That(requirement[scheme], Is.Empty);
        }
    }
}
