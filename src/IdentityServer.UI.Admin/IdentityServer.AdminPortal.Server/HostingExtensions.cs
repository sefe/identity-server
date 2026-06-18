using System.Diagnostics.CodeAnalysis;
using System.Reflection;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.AdminPortal.Server.ExceptionHandlers;
using IdentityServer.AdminPortal.Server.Infrastructure;
using IdentityServer.Core;
using IdentityServer.Core.Caching;
using IdentityServer.Core.Extensions;
using IdentityServer.Core.Infrastructure;
using IdentityServer.Core.Serilog.Extensions;
using IdentityServer.MicrosoftGraph.Extensions;
using static IdentityServer.Abstraction.Constants;
using static IdentityServer.Data.RegisterServices;

namespace IdentityServer.AdminPortal.Server;

[ExcludeFromCodeCoverage]
public static class HostingExtensions
{
    public static WebApplication ConfigureServices(this WebApplicationBuilder builder, string environment)
    {
        if (builder.Environment.IsDevelopment())
        {
            builder.Services.AddDatabaseDeveloperPageExceptionFilter();
        }

        builder.Services.ConfigureRetryPolicy(builder.Configuration);

        builder.Services.AddControllers(options =>
            {
                options.ModelBinderProviders.Insert(0, new TrimModelBinderProvider());
            })
            .AddJsonOptions(options =>
        {
            options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        });

        builder.Services.AddProblemDetails();
        builder.Services.AddExceptionHandler<EntityAccessExceptionHandler>();
        builder.Services.AddExceptionHandler<EntityAlreadyExistsExceptionHandler>();
        builder.Services.AddExceptionHandler<EntityNotFoundExceptionHandler>();
        builder.Services.AddExceptionHandler<EntityReferenceExceptionHandler>();
        builder.Services.AddExceptionHandler<EntityValidationExceptionHandler>();
        builder.Services.AddExceptionHandler<ImportValidationExceptionHandler>();
        builder.Services.AddExceptionHandler<InvalidSearchValueExceptionHandler>();
        builder.Services.AddExceptionHandler<ModelBindingExceptionHandler>();
        builder.Services.AddExceptionHandler<UserClaimExceptionHandler>();
        builder.Services.AddExceptionHandler<UserInsufficientRoleExceptionHandler>();
        builder.Services.AddExceptionHandler<DefaultExceptionHandler>();

        builder.Services.AddDataLayerForUi();

        var connectionString = builder.Configuration.GetConnectionString("IDPDBConnectionString");
        ArgumentException.ThrowIfNullOrEmpty(connectionString);
        builder.Services.AddConfigurationDbContext(optionsBuilder =>
        {
            // https://learn.microsoft.com/en-us/ef/core/logging-events-diagnostics/extensions-logging?tabs=v3#detailed-query-exceptions
            optionsBuilder.EnableDetailedErrors();
            optionsBuilder.UseSqlServer(connectionString, options => options.EnableRetryOnFailure());

            // Enable EF Core logging in Development for SQL query analysis
            if (builder.Environment.IsDevelopment())
            {
                optionsBuilder.LogTo(Console.WriteLine, LogLevel.Information);
                optionsBuilder.EnableSensitiveDataLogging();
            }
        });

        var idpAuthority = builder.Configuration["IdentityServerProvider:Authority"] ?? throw new ArgumentException("IdentityServerProvider:Authority is not defined");

        builder.Services
            .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                options.Authority = idpAuthority;
                options.Audience = ApiResourceIds.IdentityServerApi;
                options.RequireHttpsMetadata = environment.Equals(EnvironmentNames.Production, StringComparison.OrdinalIgnoreCase);

                options.MapInboundClaims = false;
                options.TokenValidationParameters.NameClaimType = "name";
                options.TokenValidationParameters.RoleClaimType = "role";
            });

        builder.Services.AddAuthorizationBuilder()
            .AddPolicy(Constants.PolicyNames.RequireReaderRole, policy =>
            {
                policy.RequireClaim(ClaimNames.Scope, ScopeNames.IdentityServerAdmin);
                policy.RequireRole(RoleNames.Reader);
            })
            .AddPolicy(Constants.PolicyNames.RequireUserRole, policy =>
            {
                policy.RequireClaim(ClaimNames.Scope, ScopeNames.IdentityServerAdmin);
                policy.RequireRole(RoleNames.User);
            });

        builder.Services.AddSingleton<IAuthorizationMiddlewareResultHandler, LoggingAuthorizationMiddlewareResultHandler>();

        var systemConfig = builder.Configuration.DirectGetSection<SystemConfig>(SystemConfig.SystemSectionName);
        var authConfig = builder.Configuration.DirectGetSection<AuthConfig>("Auth");
        var retryPolicyConfig = builder.Configuration.GetHttpRetryPolicy();

        if (string.IsNullOrEmpty(authConfig.ReaderGroupId) || string.IsNullOrEmpty(authConfig.ContributorGroupId))
        {
            throw new InvalidOperationException("Reader and/or Contributors Group are not configured in appsettings ('Auth' section).");
        }

        var entraConfig = builder.Configuration.DirectGetSection<MicrosoftEntraConfig>(Core.Constants.ConfigSections.Entra);
        if (string.IsNullOrEmpty(entraConfig.ClientId) || string.IsNullOrEmpty(entraConfig.TenantId) || string.IsNullOrEmpty(entraConfig.ClientSecret))
        {
            throw new InvalidOperationException("Microsoft Entra Client ID and/or Client Secret are not configured in appsettings ('MicrosoftEntra' section).");
        }
        var entraCacheConfig = builder.Configuration.DirectGetSection<MicrosoftEntraCacheConfig>(Core.Constants.ConfigSections.EntraCache);

        var identityServerCachingOptions = builder.Configuration.DirectGetSection<IdentityServerCachingOptions>("IdentityServer:CachingOptions");

        if (identityServerCachingOptions.Enabled)
        {
            switch (identityServerCachingOptions.Provider.Kind)
            {
                case CacheProviderKind.InMemory:
                    builder.Services.AddMemoryCache();
                    builder.Services.AddSingleton(typeof(ICache<>), typeof(MemoryCacheWrapper<>));
                    break;
                case CacheProviderKind.Valkey:
                    var redisOptions = RedisConnectionStringBuilder.BuildFrom(identityServerCachingOptions.Provider);
                    builder.Services.AddRedisConnection(redisOptions);
                    builder.Services.AddSingleton(typeof(ICache<>), typeof(RedisCache<>));
                    break;
                default:
                    throw new InvalidOperationException($"Unsupported caching provider: '{identityServerCachingOptions.Provider}'");
            }
        }
        else
        {
            builder.Services.AddSingleton(typeof(ICache<>), typeof(NoOpCache<>));
        }

        builder.Services.AddSingleton<ISystemConfig>(systemConfig);
        builder.Services.AddSingleton<IAuthConfig>(authConfig);
        builder.Services.AddSingleton<IMicrosoftEntraConfig>(entraConfig);
        builder.Services.AddSingleton<IMicrosoftEntraCacheConfig>(entraCacheConfig);

        // Configure SecretExpiration settings
        builder.Services.Configure<SecretExpirationConfig>(builder.Configuration.GetSection(SecretExpirationConfig.SectionName));

        builder.Services.AddMicrosoftGraphAuth(entraConfig)
                .AddMicrosoftGraphApplicationClient(retryPolicyConfig)
                .AddMicrosoftGraphGroupClient(retryPolicyConfig)
                .AddMicrosoftGraphUserClient(retryPolicyConfig)
                .AddCaching(entraCacheConfig);

        builder.Services.AddHttpContextAccessor();
        builder.Services.AddScoped<ICurrentUserService, CurrentUserService>();

        builder.Services.AddSwaggerGen(options =>
        {
            options.IncludeXmlComments(Assembly.GetExecutingAssembly());

            options.SwaggerDoc("v1", new OpenApiInfo
            {
                Title = "Identity Server Admin Portal API",
                Version = "v1",
                Description = "An API to configure Identity Server",
            });

            var scheme = new OpenApiSecurityScheme
            {
                In = ParameterLocation.Header,
                Name = "Authorization",
                Flows = new OpenApiOAuthFlows
                {
                    AuthorizationCode = new OpenApiOAuthFlow
                    {
                        AuthorizationUrl = new Uri($"{idpAuthority}/connect/authorize"),
                        TokenUrl = new Uri($"{idpAuthority}/connect/token"),
                    }
                },
                Type = SecuritySchemeType.OAuth2
            };
            options.AddSecurityDefinition("OAuth", scheme);
            options.AddSecurityRequirement(new OpenApiSecurityRequirement
            {
                {
                    new OpenApiSecurityScheme
                    {
                        Reference = new OpenApiReference { Id = "OAuth", Type = ReferenceType.SecurityScheme }
                    },
                    new List<string>()
                }
            });
        });

        builder.Services.AddHealthChecks();

        return builder.Build();
    }

    public static WebApplication ConfigurePipeline(this WebApplication app)
    {
        var systemConfig = app.Configuration.DirectGetSection<SystemConfig>(SystemConfig.SystemSectionName);
        var logRequestBodyFlag = app.Configuration.GetValue<bool>("Features:EnableRequestBodyLogging");

        app.UseSerilogRequestCustomLogging((diagnosticContext, httpContext) =>
        {
            diagnosticContext.ConfigureRequestStandardLogging(httpContext);
            if (logRequestBodyFlag)
            {
                diagnosticContext.TryAddValueFromHttpContext(httpContext, CustomContextFields.RequestBody);
            }
        });

        if (app.Environment.IsDevelopment())
        {
            app.UseWebAssemblyDebugging();
            app.UseExceptionHandler("/error-development");
        }
        else
        {
            // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
            app.UseHsts();
            app.UseExceptionHandler("/error");
        }

        app.UseSwagger();
        app.UseSwaggerUI(options =>
        {
            options.SwaggerEndpoint("/swagger/v1/swagger.json", "Identity Server Admin Portal API v1");

            options.OAuthClientId("identityserver.admin");
            options.OAuthScopes("openid", "profile", "identityserver.admin");
            options.OAuthUsePkce();

            options.InjectStylesheet("/css/swagger.css");

            if (app.Environment.IsDevelopment())
            {
                options.EnablePersistAuthorization();
            }
        });

        app.UseHttpsRedirection();
        app.UseBlazorFrameworkFiles();
        app.UseStaticFiles();

        app.UseLoadBalancerForwardedHeaders(systemConfig.LoadBalancer);

        app.UseRouting();

        app.UseAuthentication();
        app.UseAuthorization();

        if (logRequestBodyFlag)
        {
            app.UseMiddleware<RequestBodyLoggingMiddleware>();
        }

        // Apply the "RequireReaderRole" policy globally (all controllers require at least "Reader")
        app.MapControllers().RequireAuthorization(Constants.PolicyNames.RequireReaderRole);

        app.MapFallbackToFile("index.html", new StaticFileOptions
        {
            OnPrepareResponse = (context) =>
            {
                if (context.Context.Request.Path.StartsWithSegments("/api"))
                {
                    context.Context.Response.StatusCode = 404;
                }
            }
        });

        return app;
    }
}
