using System.Diagnostics.CodeAnalysis;
using Azure.Core;
using Azure.Identity;
using Duende.IdentityServer;
using Duende.IdentityServer.ResponseHandling;
using Duende.IdentityServer.Services;
using Duende.IdentityServer.Validation;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.IdentityModel.Tokens;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Configs;
using IdentityServer.Core;
using IdentityServer.Core.Caching;
using IdentityServer.Core.Extensions;
using IdentityServer.Core.Infrastructure;
using IdentityServer.Core.Serilog.Extensions;
using IdentityServer.Data;
using IdentityServer.Data.DbContexts;
using IdentityServer.Data.Services;
using IdentityServer.Data.Utilities;
using IdentityServer.Extensions;
using IdentityServer.MicrosoftGraph.Extensions;
using IdentityServer.Services;
using IdentityServer.Services.ApiRoles;
using IdentityServer.Services.ClientRoles;
using IdentityServer.Services.Validation;

namespace IdentityServer;

[ExcludeFromCodeCoverage]
internal static class HostingExtensions
{
    public static WebApplication ConfigureServices(this WebApplicationBuilder builder, string environment)
    {
        string dbConnectionString = builder.Configuration.GetConnectionString("IDPDBConnectionString")!;

        var entraConfig = builder.ConfigureMicrosoftEntra();
        var azCredential = GetAzureCredential(entraConfig);
        builder.ConfigureDataProtection(azCredential);

        builder.Services.AddSingleton<ISystemConfig>(builder.Configuration.DirectGetSection<SystemConfig>(SystemConfig.SystemSectionName));
        builder.Services.AddDataLayerForApi();

        var licenseKey = builder.GetDuendeLicenseKey(azCredential);

        var customIdentityServerOptions = builder.Configuration.DirectGetSection<CustomIdentityServerOptions>(CustomIdentityServerOptions.SectionName);

        var idsBuilder = builder.Services.AddIdentityServer(options =>
        {
            options.Authentication = customIdentityServerOptions.AuthenticationOptions;

            options.Caching = customIdentityServerOptions.CachingOptions.Duende;

            options.Events.RaiseSuccessEvents = true;
            options.Events.RaiseFailureEvents = true;
            options.Events.RaiseErrorEvents = true;
            options.Events.RaiseInformationEvents = true;

            options.LicenseKey = licenseKey;

            options.Preview.EnableDiscoveryDocumentCache = true;
            options.Preview.DiscoveryDocumentCacheDuration = TimeSpan.FromMinutes(1);

            options.Discovery.ShowApiScopes = false;
            options.Discovery.ShowClaims = false;
            options.Discovery.ShowIdentityScopes = false;
            options.Discovery.ShowResponseModes = false;
        })
            .ConfigureIdentityServerStores(dbConnectionString, options => options.EnableRetryOnFailure())
            .AddProfileService<CustomProfileService>()
            .AddCustomTokenRequestValidator<ApiClientCredentialsRoleMapper>()
            .AddExtensionGrantValidator<CustomTokenExchangeGrantValidator>()
            .AddClientConfigurationValidator<CustomClientConfigurationValidator>()
            .AddResourceValidator<ApiResourceIsEnabledValidator>();

        if (customIdentityServerOptions.CachingOptions.Enabled)
        {
            switch (customIdentityServerOptions.CachingOptions.Provider.Kind)
            {
                case CacheProviderKind.InMemory:
                    // cache for own code purposes
                    builder.Services.AddMemoryCache();
                    builder.Services.AddSingleton(typeof(Abstraction.Contracts.ICache<>), typeof(MemoryCacheWrapper<>));
                    // Duende cache
                    idsBuilder.AddConfigurationStoreCache();
                    break;
                case CacheProviderKind.Valkey:
                    // Setup Redis
                    var redisOptions = RedisConnectionStringBuilder.BuildFrom(customIdentityServerOptions.CachingOptions.Provider);
                    builder.Services.AddRedisConnection(redisOptions);
                    // cache for own code purposes
                    builder.Services.AddSingleton(typeof(Abstraction.Contracts.ICache<>), typeof(RedisCache<>));
                    // Duende cache
                    idsBuilder.AddConfigurationStoreCache(typeof(DuendeRedisCache<>));
                    break;
                default:
                    throw new InvalidOperationException($"Unsupported caching provider: '{customIdentityServerOptions.CachingOptions.Provider}'");
            }
        }
        else
        {
            builder.Services.AddSingleton(typeof(Abstraction.Contracts.ICache<>), typeof(NoOpCache<>));
        }

        // Feature flag for RedirectUriValidator
        var useCustomRedirectUriValidator = builder.Configuration.GetValue<bool>("FeatureFlags:UseCustomRedirectUriValidator");
        if (useCustomRedirectUriValidator)
        {
            builder.Services.AddTransient<IRedirectUriValidator, LoopbackDynamicPortRedirectUriValidator>();
        }
        var useCustomTokenLogging = builder.Configuration.GetValue<bool>("FeatureFlags:CustomTokenLoggingSettings:EnableCustomTokenLogging");
        if (useCustomTokenLogging)
        {
            builder.Services.Configure<CustomTokenLoggingSettings>(builder.Configuration.GetSection("FeatureFlags:CustomTokenLoggingSettings"));
            builder.Services.AddTransient<ITokenService, CustomLoggingTokenService>();
            builder.Services.Decorate<IIntrospectionRequestValidator, CustomIntrospectionRequestValidator>();
        }

        builder.Services.AddTransient<IClientSecretValidator, CustomClientSecretValidator>();
        builder.Services.AddProblemDetails();
        builder.Services.AddExceptionHandler<EntityReferenceExceptionHandler>();
        builder.Services.AddExceptionHandler<UserAuthenticationExceptionHandler>();
        builder.Services.AddExceptionHandler<DefaultExceptionHandler>();
        builder.Services.AddScoped<IApiUserRoleClaimMapper, ApiUserRoleClaimMapper>();
        builder.Services.AddScoped<IApiClientRoleClaimMapper, ApiClientRoleClaimMapper>();
        builder.Services.AddScoped<IClientUserRoleClaimMapper, ClientUserRoleClaimMapper>();
        builder.Services.AddScoped<IReportingService, ReportingService>();
        builder.Services.AddTransient<ITokenResponseGenerator, CustomTokenResponseGenerator>();

        builder.Services.AddAuthorizationBuilder()
            .AddPolicy(Constants.Policies.M2MClientsRead, policy =>
            {
                policy.RequireClaim(Abstraction.Constants.ClaimNames.M2M, bool.TrueString);
                policy.RequireClaim(Abstraction.Constants.ClaimNames.Scope, Abstraction.Constants.ScopeNames.IdentityServerClientsRead);
            })
            .AddPolicy(Constants.Policies.M2MReportsRead, policy =>
            {
                policy.RequireClaim(Abstraction.Constants.ClaimNames.M2M, bool.TrueString);
                policy.RequireClaim(Abstraction.Constants.ClaimNames.Scope, Abstraction.Constants.ScopeNames.IdentityServerReportsRead);
            });

        builder.Services.AddSingleton<IAuthorizationMiddlewareResultHandler, LoggingAuthorizationMiddlewareResultHandler>();

        builder.Services.AddControllers();
        builder.Services.AddRazorPages();
        builder.Services.AddHealthChecks();
        if (!Abstraction.Constants.EnvironmentNames.Production.Equals(environment, StringComparison.OrdinalIgnoreCase))
        {
            builder.AddSwagger();
        }

        builder.Services.AddTransient<IEventSink, IdentityServerEventSink>();
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddScoped<ICurrentUserService, CurrentUserService>();

        return builder.Build();
    }

    private static void AddSwagger(this WebApplicationBuilder builder)
    {
        builder.Services.AddSwaggerGen(options =>
        {
            options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
            {
                Title = "Identity Server API",
                Version = "v1",
                Description = "An API to facilitate OAuth connectivity",
            });

            options.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
            {
                In = Microsoft.OpenApi.Models.ParameterLocation.Header,
                Description = "Please enter token",
                Name = "Authorization",
                Type = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
                Scheme = "bearer",
                BearerFormat = "JWT"
            });

            options.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
                {
                { new Microsoft.OpenApi.Models.OpenApiSecurityScheme
                    {
                        Reference = new Microsoft.OpenApi.Models.OpenApiReference
                        {
                            Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
                            Id = "Bearer"
                        }
                    },
                    Array.Empty<string>() }
                });
        });
    }

    private static MicrosoftEntraConfig ConfigureMicrosoftEntra(this WebApplicationBuilder builder)
    {
        builder.Services.ConfigureRetryPolicy(builder.Configuration);
        var retryPolicyConfig = builder.Configuration.GetHttpRetryPolicy();

        var entraConfig = builder.Configuration.DirectGetSection<MicrosoftEntraConfig>(Core.Constants.ConfigSections.Entra);
        var entraCacheConfig = builder.Configuration.DirectGetSection<MicrosoftEntraCacheConfig>(Core.Constants.ConfigSections.EntraCache);

        builder.Services.AddSingleton<IMicrosoftEntraConfig>(entraConfig);
        builder.Services.AddSingleton<IMicrosoftEntraCacheConfig>(entraCacheConfig);

        builder.Services.AddMicrosoftGraphAuth(entraConfig)
                    .AddMicrosoftGraphApplicationClient(retryPolicyConfig)
                    .AddMicrosoftGraphGroupClient(retryPolicyConfig)
                    .AddMicrosoftGraphUserClient(retryPolicyConfig)
                    .AddCaching(entraCacheConfig);

        var idpAuthority = builder.Configuration["IdentityServerProvider:Authority"]
                    ?? throw new ArgumentException("IdentityServerProvider:Authority is not defined");

        var entraIssuer10 = $"https://sts.windows.net/{entraConfig.TenantId}/";
        var entraIssuer20 = $"https://login.microsoftonline.com/{entraConfig.TenantId}/v2.0";

        var schemeIssuerMapping = new AuthSchemeIssuerMapping();
        schemeIssuerMapping.IssuerToSchemeMap.Add(entraIssuer10, Constants.AuthenticationSchemes.EntraId_JWT_Bearer);
        schemeIssuerMapping.IssuerToSchemeMap.Add(entraIssuer20, Constants.AuthenticationSchemes.EntraId_JWT_Bearer);
        builder.Services.AddSingleton(schemeIssuerMapping);

        builder.Services.AddTransient<ITokenValidatorSelector, TokenValidatorSelector>(sp =>
            new TokenValidatorSelector(
                sp.GetRequiredService<ITokenValidator>(),
                sp.GetRequiredService<AuthSchemeIssuerMapping>(),
                sp.GetRequiredService<ILogger<TokenValidatorSelector>>(),
                sp
            )
        );

        builder.Services
            .AddAuthentication()
            .AddOpenIdConnect("EntraID", "Entra ID", options =>
            {
                options.ClientId = entraConfig.ClientId;
                options.ClientSecret = entraConfig.ClientSecret;
                options.Authority = entraIssuer20;
                options.SignInScheme = IdentityServerConstants.ExternalCookieAuthenticationScheme;

                options.Scope.Add("profile");
                options.Scope.Add("openid");
                options.Scope.Add("email");

                options.MapInboundClaims = false;
                options.ClaimActions.MapJsonKey(Abstraction.Constants.ClaimNamesEntra.UserGroups, Abstraction.Constants.ClaimNames.UserGroups);
                options.TokenValidationParameters.NameClaimType = "name";
                options.TokenValidationParameters.RoleClaimType = "role";

                ConfigureOpenIdConnectEvents(options);

            })
            .AddJwtBearer(Constants.AuthenticationSchemes.EntraId_JWT_Bearer, options =>
            {
                options.Authority = entraIssuer20;
                options.MapInboundClaims = false;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuers = new[] {
                        entraIssuer20,
                        entraIssuer10,
                    },
                    ValidateAudience = true,
                    ValidAudiences = new[] { $"api://{entraConfig.ClientId}" }, // convention
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                };
            })
            .AddJwtBearer(Constants.AuthenticationSchemes.API_JWT_Bearer, options =>
            {
                options.MapInboundClaims = false;

                options.Authority = idpAuthority;
                options.Audience = Abstraction.Constants.ApiResourceIds.IdentityServerApi;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidIssuer = idpAuthority,
                    NameClaimType = "name",
                    RoleClaimType = "role"
                };
                options.Events = new JwtBearerEvents
                {
                    OnAuthenticationFailed = context =>
                                    {
                                        var logger = context.HttpContext.RequestServices.GetRequiredService<ILogger<JwtBearerEvents>>();
                                        logger.LogError("JWT authentication failed: {Error}", context.Exception.Message);
                                        return Task.CompletedTask;
                                    }
                };
            });

        return entraConfig;
    }

    private static ClientSecretCredential GetAzureCredential(MicrosoftEntraConfig entraConfig)
    {
        return new ClientSecretCredential(entraConfig.TenantId, entraConfig.ClientId, entraConfig.ClientSecret);
    }

    private static string GetDuendeLicenseKey(this WebApplicationBuilder builder, TokenCredential credential)
    {
        var kvConfig = builder.Configuration.GetRequiredSection("AzureKeyVaultConnections:IdentityServerLicenseKey").Get<KeyVaultObjectConfig>() ??
            throw new InvalidOperationException($"AzureKeyVaultConnections:IdentityServerLicenseKey configuration section is not present or could not be parsed properly.");

        try
        {
            var secretClient = new Azure.Security.KeyVault.Secrets.SecretClient(new Uri(kvConfig.KeyVaultUrl), credential);
            var licenseKeySecret = secretClient.GetSecret(kvConfig.ObjectName);
            return licenseKeySecret.Value.Value;
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"Failed to retrieve IdentityServer license key ({kvConfig.ObjectName}) from Azure Key Vault ({kvConfig.KeyVaultUrl}).", ex);
        }
    }

    private static void ConfigureDataProtection(this WebApplicationBuilder builder, TokenCredential credentials)
    {
        var kvConfig = builder.Configuration.GetRequiredSection("AzureKeyVaultConnections:DataProtectionEncryptionKeyConfig").Get<KeyVaultObjectConfig>();

        builder.Services
            .AddDataProtection()
            .SetApplicationName($"IdentityServer.API-{builder.Environment.EnvironmentName}")
            .PersistKeysToDbContext<IdentityServerOperationalDbContext>()
            .ProtectKeysWithAzureKeyVault(new Uri($"{kvConfig!.KeyVaultUrl}/keys/{kvConfig.ObjectName}/"), credentials);
    }

    private static void ConfigureOpenIdConnectEvents(OpenIdConnectOptions options)
    {
        options.Events = new OpenIdConnectEvents
        {
            //signin-oidc failures
            OnRemoteFailure = context =>
            {
                // Correlatetion cookies .AspNetCore.Correlation.*** and .AspNetCore.OpenIdConnect.Nonce.*** must match these issued by the Challenge endpoint and coded in the state token returned by the Entra.
                // Extend with other issues and more custom handling as needed.
                if (context.Failure != null)
                {
                    throw new UserAuthenticationException("Remote authentication failure", context.Failure);
                }

                return Task.CompletedTask;
            }
        };
    }

    public static WebApplication ConfigurePipeline(this WebApplication app, string environment)
    {
        var systemConfig = app.Configuration.DirectGetSection<SystemConfig>(SystemConfig.SystemSectionName);

        app.UseSerilogRequestDuendeLogging();

        if (app.Environment.IsDevelopment())
        {
            app.UseDeveloperExceptionPage();
        }

        if (!Abstraction.Constants.EnvironmentNames.Production.Equals(environment, StringComparison.OrdinalIgnoreCase))
        {
            app.UseSwagger();
            app.UseSwaggerUI();
        }

        app.UseExceptionHandler();

        app.UseStaticFiles();
        app.UseLoadBalancerForwardedHeaders(systemConfig.LoadBalancer);
        app.UseRouting();
        app.UseAuthorization();
        app.UseIdentityServer();
        app.MapControllers();
        app.MapRazorPages()
            .RequireAuthorization();

        return app;
    }
}
