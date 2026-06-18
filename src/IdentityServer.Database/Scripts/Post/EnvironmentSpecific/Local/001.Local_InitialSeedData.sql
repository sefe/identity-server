IF (NOT EXISTS (SELECT 1 FROM [dbo].[ApiResources] WHERE [Name] = 'identityserver'))
BEGIN
    ALTER TABLE [dbo].[ClientPostLogoutRedirectUris] DROP CONSTRAINT [FK_ClientPostLogoutRedirectUris_Clients_ClientId]
    ALTER TABLE [dbo].[ClientSecrets] DROP CONSTRAINT [FK_ClientSecrets_Clients_ClientId]
    ALTER TABLE [dbo].[ApiResourceScopes] DROP CONSTRAINT [FK_ApiResourceScopes_ApiResources_ApiResourceId]
    ALTER TABLE [dbo].[IdentityResourceClaims] DROP CONSTRAINT [FK_IdentityResourceClaims_IdentityResources_IdentityResourceId]
    ALTER TABLE [dbo].[ApiResourceProperties] DROP CONSTRAINT [FK_ApiResourceProperties_ApiResources_ApiResourceId]
    ALTER TABLE [dbo].[ApiResourceRoles] DROP CONSTRAINT [FK_ApiResourceRoles_ApiResources_ApiResourceId]
    ALTER TABLE [dbo].[ClientIdPRestrictions] DROP CONSTRAINT [FK_ClientIdPRestrictions_Clients_ClientId]
    ALTER TABLE [dbo].[ApiResourceClaims] DROP CONSTRAINT [FK_ApiResourceClaims_ApiResources_ApiResourceId]
    ALTER TABLE [dbo].[ClientGrantTypes] DROP CONSTRAINT [FK_ClientGrantTypes_Clients_ClientId]
    ALTER TABLE [dbo].[ClientCorsOrigins] DROP CONSTRAINT [FK_ClientCorsOrigins_Clients_ClientId]
    ALTER TABLE [dbo].[ClientScopes] DROP CONSTRAINT [FK_ClientScopes_Clients_ClientId]
    ALTER TABLE [dbo].[ClientClaims] DROP CONSTRAINT [FK_ClientClaims_Clients_ClientId]
    ALTER TABLE [dbo].[IdentityResourceProperties] DROP CONSTRAINT [FK_IdentityResourceProperties_IdentityResources_IdentityResourceId]
    ALTER TABLE [dbo].[ApiScopeClaims] DROP CONSTRAINT [FK_ApiScopeClaims_ApiScopes_ScopeId]
    ALTER TABLE [dbo].[RoleMappings] DROP CONSTRAINT [FK_RoleMappings_RoleMappingTypes_RoleMappingTypeId]
    ALTER TABLE [dbo].[RoleMappings] DROP CONSTRAINT [FK_RoleMappings_ApiResourceRoles_ApiResourceRoleId]
    ALTER TABLE [dbo].[ApiScopeProperties] DROP CONSTRAINT [FK_ApiScopeProperties_ApiScopes_ScopeId]
    ALTER TABLE [dbo].[ApiResourceSecrets] DROP CONSTRAINT [FK_ApiResourceSecrets_ApiResources_ApiResourceId]
    ALTER TABLE [dbo].[SystemPermissionRole] DROP CONSTRAINT [FK_SystemPermissionRole_SystemPermissionEnvironments_SystemPermissionEnvironmentId]
    ALTER TABLE [dbo].[ClientProperties] DROP CONSTRAINT [FK_ClientProperties_Clients_ClientId]
    ALTER TABLE [dbo].[ClientRedirectUris] DROP CONSTRAINT [FK_ClientRedirectUris_Clients_ClientId]
    ALTER TABLE [dbo].[Clients] DROP CONSTRAINT [FK_Clients_SystemPermissionEnvironments_SystemPermissionEnvironmentId]
    ALTER TABLE [dbo].[ApiResources] DROP CONSTRAINT [FK_ApiResources_SystemPermissionEnvironments_SystemPermissionEnvironmentId]
    ALTER TABLE [dbo].[SystemPermissionEnvironments] DROP CONSTRAINT [FK_SystemPermissionEnvironments_SystemPermissions_SystemPermissionId]

    declare @local_SystemPermissionEnvironmentId int 
    select @local_SystemPermissionEnvironmentId = ID from [dbo].[SystemPermissionEnvironments] where [Environment] = N'Development'

    SET IDENTITY_INSERT [dbo].[ApiResources] ON
    INSERT INTO [dbo].[ApiResources] ([Id], [Enabled], [Name], [DisplayName], [Description], [AllowedAccessTokenSigningAlgorithms], [ShowInDiscoveryDocument], [RequireResourceIndicator], [Created], [Updated], [LastAccessed], [NonEditable], [Discriminator], [SystemPermissionEnvironmentId]) VALUES (1, 1, N'identityserver', N'Identity Server Admin API', N'identity server api resource', NULL, 1, 0, SYSUTCDATETIME(), NULL, NULL, 0, N'ApiResourceExt', @local_SystemPermissionEnvironmentId)
    SET IDENTITY_INSERT [dbo].[ApiResources] OFF

    SET IDENTITY_INSERT [dbo].[Clients] ON
    INSERT INTO [dbo].[Clients] ([Id], [Enabled], [ClientId], [ProtocolType], [RequireClientSecret], [ClientName], [Description], [ClientUri], [LogoUri], [RequireConsent], [AllowRememberConsent], [AlwaysIncludeUserClaimsInIdToken], [RequirePkce], [AllowPlainTextPkce], [RequireRequestObject], [AllowAccessTokensViaBrowser], [RequireDPoP], [DPoPValidationMode], [DPoPClockSkew], [FrontChannelLogoutUri], [FrontChannelLogoutSessionRequired], [BackChannelLogoutUri], [BackChannelLogoutSessionRequired], [AllowOfflineAccess], [IdentityTokenLifetime], [AllowedIdentityTokenSigningAlgorithms], [AccessTokenLifetime], [AuthorizationCodeLifetime], [ConsentLifetime], [AbsoluteRefreshTokenLifetime], [SlidingRefreshTokenLifetime], [RefreshTokenUsage], [UpdateAccessTokenClaimsOnRefresh], [RefreshTokenExpiration], [AccessTokenType], [EnableLocalLogin], [IncludeJwtId], [AlwaysSendClientClaims], [ClientClaimsPrefix], [PairWiseSubjectSalt], [InitiateLoginUri], [UserSsoLifetime], [UserCodeType], [DeviceCodeLifetime], [CibaLifetime], [PollingInterval], [CoordinateLifetimeWithUserSession], [Created], [Updated], [LastAccessed], [NonEditable], [PushedAuthorizationLifetime], [RequirePushedAuthorization], [Discriminator], [SystemPermissionEnvironmentId]) VALUES (1, 1, N'identityserver.admin', N'oidc', 0, N'Identity Server Admin', NULL, NULL, NULL, 0, 1, 1, 1, 0, 0, 0, 0, 1, '00:05:00.0000000', NULL, 1, NULL, 1, 1, 300, NULL, 3600, 300, NULL, 2592000, 1296000, 0, 1, 1, 0, 0, 1, 1, NULL, NULL, NULL, NULL, NULL, 300, NULL, NULL, NULL, SYSUTCDATETIME(), NULL, NULL, 0, NULL, 0, N'ClientExt', @local_SystemPermissionEnvironmentId)
    INSERT INTO [dbo].[Clients] ([Id], [Enabled], [ClientId], [ProtocolType], [RequireClientSecret], [ClientName], [Description], [ClientUri], [LogoUri], [RequireConsent], [AllowRememberConsent], [AlwaysIncludeUserClaimsInIdToken], [RequirePkce], [AllowPlainTextPkce], [RequireRequestObject], [AllowAccessTokensViaBrowser], [RequireDPoP], [DPoPValidationMode], [DPoPClockSkew], [FrontChannelLogoutUri], [FrontChannelLogoutSessionRequired], [BackChannelLogoutUri], [BackChannelLogoutSessionRequired], [AllowOfflineAccess], [IdentityTokenLifetime], [AllowedIdentityTokenSigningAlgorithms], [AccessTokenLifetime], [AuthorizationCodeLifetime], [ConsentLifetime], [AbsoluteRefreshTokenLifetime], [SlidingRefreshTokenLifetime], [RefreshTokenUsage], [UpdateAccessTokenClaimsOnRefresh], [RefreshTokenExpiration], [AccessTokenType], [EnableLocalLogin], [IncludeJwtId], [AlwaysSendClientClaims], [ClientClaimsPrefix], [PairWiseSubjectSalt], [InitiateLoginUri], [UserSsoLifetime], [UserCodeType], [DeviceCodeLifetime], [CibaLifetime], [PollingInterval], [CoordinateLifetimeWithUserSession], [Created], [Updated], [LastAccessed], [NonEditable], [PushedAuthorizationLifetime], [RequirePushedAuthorization], [Discriminator], [SystemPermissionEnvironmentId]) VALUES (2, 1, N'identityserver.client', N'oidc', 0, N'Identity Server Client UI', NULL, NULL, NULL, 0, 1, 1, 1, 0, 0, 0, 0, 1, '00:05:00.0000000', NULL, 1, NULL, 1, 1, 300, NULL, 3600, 300, NULL, 2592000, 1296000, 0, 1, 1, 0, 0, 1, 1, NULL, NULL, NULL, NULL, NULL, 300, NULL, NULL, NULL, SYSUTCDATETIME(), NULL, NULL, 0, NULL, 0, N'ClientExt', @local_SystemPermissionEnvironmentId)
    SET IDENTITY_INSERT [dbo].[Clients] OFF

    SET IDENTITY_INSERT [dbo].[ClientRedirectUris] ON
    INSERT INTO [dbo].[ClientRedirectUris] ([Id], [RedirectUri], [ClientId]) VALUES (1, N'https://localhost:5300/authentication/login-callback', 1)
    INSERT INTO [dbo].[ClientRedirectUris] ([Id], [RedirectUri], [ClientId]) VALUES (2, N'https://localhost:5300/swagger/oauth2-redirect.html', 1)
    INSERT INTO [dbo].[ClientRedirectUris] ([Id], [RedirectUri], [ClientId]) VALUES (3, N'https://identityserverdv:5300/authentication/login-callback', 1)
    INSERT INTO [dbo].[ClientRedirectUris] ([Id], [RedirectUri], [ClientId]) VALUES (4, N'https://identityserverdv:5300/swagger/oauth2-redirect.html', 1)
    INSERT INTO [dbo].[ClientRedirectUris] ([Id], [RedirectUri], [ClientId]) VALUES (5, N'https://localhost:5400/authentication/login-callback', 2)
    SET IDENTITY_INSERT [dbo].[ClientRedirectUris] OFF

    SET IDENTITY_INSERT [dbo].[ApiScopes] ON
    INSERT INTO [dbo].[ApiScopes] ([Id], [Enabled], [Name], [DisplayName], [Description], [Required], [Emphasize], [ShowInDiscoveryDocument], [Created], [Updated], [LastAccessed], [NonEditable]) VALUES (1, 1, N'identityserver.admin', N'Full access', NULL, 0, 0, 1, SYSUTCDATETIME(), NULL, NULL, 0)
    SET IDENTITY_INSERT [dbo].[ApiScopes] OFF

    -- Differ by AD group
    SET IDENTITY_INSERT [dbo].[RoleMappings] ON
    INSERT INTO [dbo].[RoleMappings] ([Id], [ApiResourceRoleId], [MappingType], [RoleMappingTypeId], [Value], [Description]) VALUES (1, 1, 1, 1, N'f555d613-ba96-495c-a757-f6c41937ea3e', N'IdentityServer-AdminPortal-DV-Admin')
    INSERT INTO [dbo].[RoleMappings] ([Id], [ApiResourceRoleId], [MappingType], [RoleMappingTypeId], [Value], [Description]) VALUES (2, 2, 1, 1, N'c5648106-3a35-48a5-8166-0f0d28ffaba0', N'IdentityServer-AdminPortal-DV-Reader')
    INSERT INTO [dbo].[RoleMappings] ([Id], [ApiResourceRoleId], [MappingType], [RoleMappingTypeId], [Value], [Description]) VALUES (3, 3, 1, 1, N'a74b0e5f-8b12-4e78-b84b-7c19c7a9eda6', N'IdentityServer-AdminPortal-DV-Security')
    INSERT INTO [dbo].[RoleMappings] ([Id], [ApiResourceRoleId], [MappingType], [RoleMappingTypeId], [Value], [Description]) VALUES (4, 4, 1, 1, N'09434888-eccb-4a7e-b444-f26c41d3d923', N'IdentityServer-AdminPortal-DV-User')
    SET IDENTITY_INSERT [dbo].[RoleMappings] OFF

    SET IDENTITY_INSERT [dbo].[IdentityResources] ON
    INSERT INTO [dbo].[IdentityResources] ([Id], [Enabled], [Name], [DisplayName], [Description], [Required], [Emphasize], [ShowInDiscoveryDocument], [Created], [Updated], [NonEditable]) VALUES (1, 1, N'openid', N'Your user identifier', NULL, 1, 0, 1, SYSUTCDATETIME(), NULL, 0)
    INSERT INTO [dbo].[IdentityResources] ([Id], [Enabled], [Name], [DisplayName], [Description], [Required], [Emphasize], [ShowInDiscoveryDocument], [Created], [Updated], [NonEditable]) VALUES (2, 1, N'profile', N'User profile', N'Your user profile information (first name, last name, etc.)', 0, 1, 1, SYSUTCDATETIME(), NULL, 0)
    INSERT INTO [dbo].[IdentityResources] ([Id], [Enabled], [Name], [DisplayName], [Description], [Required], [Emphasize], [ShowInDiscoveryDocument], [Created], [Updated], [NonEditable]) VALUES (3, 1, N'email', N'Your primary and secondary email(s)', NULL, 0, 0, 1, SYSUTCDATETIME(), NULL, 0)
    SET IDENTITY_INSERT [dbo].[IdentityResources] OFF

    SET IDENTITY_INSERT [dbo].[ClientScopes] ON
    INSERT INTO [dbo].[ClientScopes] ([Id], [Scope], [ClientId]) VALUES (1, N'openid', 1)
    INSERT INTO [dbo].[ClientScopes] ([Id], [Scope], [ClientId]) VALUES (2, N'profile', 1)
    INSERT INTO [dbo].[ClientScopes] ([Id], [Scope], [ClientId]) VALUES (3, N'email', 1)
    INSERT INTO [dbo].[ClientScopes] ([Id], [Scope], [ClientId]) VALUES (4, N'identityserver.admin', 1)
    INSERT INTO [dbo].[ClientScopes] ([Id], [Scope], [ClientId]) VALUES (5, N'openid', 2)
    INSERT INTO [dbo].[ClientScopes] ([Id], [Scope], [ClientId]) VALUES (6, N'profile', 2)
    INSERT INTO [dbo].[ClientScopes] ([Id], [Scope], [ClientId]) VALUES (7, N'email', 2)
    INSERT INTO [dbo].[ClientScopes] ([Id], [Scope], [ClientId]) VALUES (8, N'identityserver.admin', 2)
    SET IDENTITY_INSERT [dbo].[ClientScopes] OFF

    SET IDENTITY_INSERT [dbo].[ClientCorsOrigins] ON
    INSERT INTO [dbo].[ClientCorsOrigins] ([Id], [Origin], [ClientId]) VALUES (1, N'https://localhost:5300', 1)
    INSERT INTO [dbo].[ClientCorsOrigins] ([Id], [Origin], [ClientId]) VALUES (2, N'https://identityserverdv:5300', 1)
    INSERT INTO [dbo].[ClientCorsOrigins] ([Id], [Origin], [ClientId]) VALUES (3, N'https://localhost:5400', 2)
    SET IDENTITY_INSERT [dbo].[ClientCorsOrigins] OFF

    SET IDENTITY_INSERT [dbo].[ClientGrantTypes] ON
    INSERT INTO [dbo].[ClientGrantTypes] ([Id], [GrantType], [ClientId]) VALUES (1, N'authorization_code', 1)
    INSERT INTO [dbo].[ClientGrantTypes] ([Id], [GrantType], [ClientId]) VALUES (2, N'authorization_code', 2)
    SET IDENTITY_INSERT [dbo].[ClientGrantTypes] OFF


    SET IDENTITY_INSERT [dbo].[ApiResourceRoles] ON
    INSERT INTO [dbo].[ApiResourceRoles] ([Id], [ApiResourceId], [RoleName], [Created], [Updated]) VALUES (1, 1, N'Admin', SYSUTCDATETIME(), NULL)
    INSERT INTO [dbo].[ApiResourceRoles] ([Id], [ApiResourceId], [RoleName], [Created], [Updated]) VALUES (2, 1, N'Reader', SYSUTCDATETIME(), NULL)
    INSERT INTO [dbo].[ApiResourceRoles] ([Id], [ApiResourceId], [RoleName], [Created], [Updated]) VALUES (3, 1, N'Security', SYSUTCDATETIME(), NULL)
    INSERT INTO [dbo].[ApiResourceRoles] ([Id], [ApiResourceId], [RoleName], [Created], [Updated]) VALUES (4, 1, N'User', SYSUTCDATETIME(), NULL)
    SET IDENTITY_INSERT [dbo].[ApiResourceRoles] OFF

    SET IDENTITY_INSERT [dbo].[IdentityResourceClaims] ON
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (1, 1, N'sub')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (2, 2, N'name')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (3, 2, N'family_name')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (4, 2, N'given_name')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (5, 2, N'middle_name')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (6, 2, N'nickname')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (7, 2, N'preferred_username')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (8, 2, N'profile')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (9, 2, N'picture')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (10, 2, N'website')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (11, 2, N'gender')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (12, 2, N'birthdate')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (13, 2, N'zoneinfo')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (14, 2, N'locale')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (15, 2, N'updated_at')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (16, 3, N'email')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (17, 3, N'verified_primary_email')
    INSERT INTO [dbo].[IdentityResourceClaims] ([Id], [IdentityResourceId], [Type]) VALUES (18, 3, N'verified_secondary_email')
    SET IDENTITY_INSERT [dbo].[IdentityResourceClaims] OFF

    SET IDENTITY_INSERT [dbo].[ApiResourceScopes] ON
    INSERT INTO [dbo].[ApiResourceScopes] ([Id], [Scope], [ApiResourceId]) VALUES (1, N'identityserver.admin', 1)
    SET IDENTITY_INSERT [dbo].[ApiResourceScopes] OFF

    SET IDENTITY_INSERT [dbo].[ClientPostLogoutRedirectUris] ON
    INSERT INTO [dbo].[ClientPostLogoutRedirectUris] ([Id], [PostLogoutRedirectUri], [ClientId]) VALUES (1, N'https://localhost:5300/bye', 1)
    INSERT INTO [dbo].[ClientPostLogoutRedirectUris] ([Id], [PostLogoutRedirectUri], [ClientId]) VALUES (2, N'https://identityserverdv:5300/bye', 1)
    SET IDENTITY_INSERT [dbo].[ClientPostLogoutRedirectUris] OFF

    ALTER TABLE [dbo].[ClientPostLogoutRedirectUris]
        ADD CONSTRAINT [FK_ClientPostLogoutRedirectUris_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ClientSecrets]
        ADD CONSTRAINT [FK_ClientSecrets_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ApiResourceScopes]
        ADD CONSTRAINT [FK_ApiResourceScopes_ApiResources_ApiResourceId] FOREIGN KEY ([ApiResourceId]) REFERENCES [dbo].[ApiResources] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[IdentityResourceClaims]
        ADD CONSTRAINT [FK_IdentityResourceClaims_IdentityResources_IdentityResourceId] FOREIGN KEY ([IdentityResourceId]) REFERENCES [dbo].[IdentityResources] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ApiResourceProperties]
        ADD CONSTRAINT [FK_ApiResourceProperties_ApiResources_ApiResourceId] FOREIGN KEY ([ApiResourceId]) REFERENCES [dbo].[ApiResources] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ApiResourceRoles]
        ADD CONSTRAINT [FK_ApiResourceRoles_ApiResources_ApiResourceId] FOREIGN KEY ([ApiResourceId]) REFERENCES [dbo].[ApiResources] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ClientIdPRestrictions]
        ADD CONSTRAINT [FK_ClientIdPRestrictions_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ApiResourceClaims]
        ADD CONSTRAINT [FK_ApiResourceClaims_ApiResources_ApiResourceId] FOREIGN KEY ([ApiResourceId]) REFERENCES [dbo].[ApiResources] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ClientGrantTypes]
        ADD CONSTRAINT [FK_ClientGrantTypes_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ClientCorsOrigins]
        ADD CONSTRAINT [FK_ClientCorsOrigins_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ClientScopes]
        ADD CONSTRAINT [FK_ClientScopes_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ClientClaims]
        ADD CONSTRAINT [FK_ClientClaims_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[IdentityResourceProperties]
        ADD CONSTRAINT [FK_IdentityResourceProperties_IdentityResources_IdentityResourceId] FOREIGN KEY ([IdentityResourceId]) REFERENCES [dbo].[IdentityResources] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ApiScopeClaims]
        ADD CONSTRAINT [FK_ApiScopeClaims_ApiScopes_ScopeId] FOREIGN KEY ([ScopeId]) REFERENCES [dbo].[ApiScopes] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[RoleMappings]
        ADD CONSTRAINT [FK_RoleMappings_RoleMappingTypes_RoleMappingTypeId] FOREIGN KEY ([RoleMappingTypeId]) REFERENCES [dbo].[RoleMappingTypes] ([Id])
    ALTER TABLE [dbo].[RoleMappings]
        ADD CONSTRAINT [FK_RoleMappings_ApiResourceRoles_ApiResourceRoleId] FOREIGN KEY ([ApiResourceRoleId]) REFERENCES [dbo].[ApiResourceRoles] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ApiScopeProperties]
        ADD CONSTRAINT [FK_ApiScopeProperties_ApiScopes_ScopeId] FOREIGN KEY ([ScopeId]) REFERENCES [dbo].[ApiScopes] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ApiResourceSecrets]
        ADD CONSTRAINT [FK_ApiResourceSecrets_ApiResources_ApiResourceId] FOREIGN KEY ([ApiResourceId]) REFERENCES [dbo].[ApiResources] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[SystemPermissionRole]
        ADD CONSTRAINT [FK_SystemPermissionRole_SystemPermissionEnvironments_SystemPermissionEnvironmentId] FOREIGN KEY ([SystemPermissionEnvironmentId]) REFERENCES [dbo].[SystemPermissionEnvironments] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ClientProperties]
        ADD CONSTRAINT [FK_ClientProperties_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[ClientRedirectUris]
        ADD CONSTRAINT [FK_ClientRedirectUris_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
    ALTER TABLE [dbo].[Clients]
        ADD CONSTRAINT [FK_Clients_SystemPermissionEnvironments_SystemPermissionEnvironmentId] FOREIGN KEY ([SystemPermissionEnvironmentId]) REFERENCES [dbo].[SystemPermissionEnvironments] ([Id])
    ALTER TABLE [dbo].[ApiResources]
        ADD CONSTRAINT [FK_ApiResources_SystemPermissionEnvironments_SystemPermissionEnvironmentId] FOREIGN KEY ([SystemPermissionEnvironmentId]) REFERENCES [dbo].[SystemPermissionEnvironments] ([Id])
    ALTER TABLE [dbo].[SystemPermissionEnvironments]
        ADD CONSTRAINT [FK_SystemPermissionEnvironments_SystemPermissions_SystemPermissionId] FOREIGN KEY ([SystemPermissionId]) REFERENCES [dbo].[SystemPermissions] ([Id]) ON DELETE CASCADE
END