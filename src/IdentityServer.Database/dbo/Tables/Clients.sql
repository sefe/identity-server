CREATE TABLE [dbo].[Clients] (
    [Id]                                    INT             IDENTITY (1, 1) NOT NULL,
    [Enabled]                               BIT             NOT NULL,
    [ClientId]                              NVARCHAR (200)  NOT NULL,
    [ProtocolType]                          NVARCHAR (200)  NOT NULL,
    [RequireClientSecret]                   BIT             NOT NULL,
    [ClientName]                            NVARCHAR (200)  NULL,
    [Description]                           NVARCHAR (1000) NULL,
    [ClientUri]                             NVARCHAR (2000) NULL,
    [LogoUri]                               NVARCHAR (2000) NULL,
    [RequireConsent]                        BIT             NOT NULL,
    [AllowRememberConsent]                  BIT             NOT NULL,
    [AlwaysIncludeUserClaimsInIdToken]      BIT             NOT NULL,
    [RequirePkce]                           BIT             NOT NULL,
    [AllowPlainTextPkce]                    BIT             NOT NULL,
    [RequireRequestObject]                  BIT             NOT NULL,
    [AllowAccessTokensViaBrowser]           BIT             NOT NULL,
    [RequireDPoP]                           BIT             NOT NULL,
    [DPoPValidationMode]                    INT             NOT NULL,
    [DPoPClockSkew]                         TIME (7)        NOT NULL,
    [FrontChannelLogoutUri]                 NVARCHAR (2000) NULL,
    [FrontChannelLogoutSessionRequired]     BIT             NOT NULL,
    [BackChannelLogoutUri]                  NVARCHAR (2000) NULL,
    [BackChannelLogoutSessionRequired]      BIT             NOT NULL,
    [AllowOfflineAccess]                    BIT             NOT NULL,
    [IdentityTokenLifetime]                 INT             NOT NULL,
    [AllowedIdentityTokenSigningAlgorithms] NVARCHAR (100)  NULL,
    [AccessTokenLifetime]                   INT             NOT NULL,
    [AuthorizationCodeLifetime]             INT             NOT NULL,
    [ConsentLifetime]                       INT             NULL,
    [AbsoluteRefreshTokenLifetime]          INT             NOT NULL,
    [SlidingRefreshTokenLifetime]           INT             NOT NULL,
    [RefreshTokenUsage]                     INT             NOT NULL,
    [UpdateAccessTokenClaimsOnRefresh]      BIT             NOT NULL,
    [RefreshTokenExpiration]                INT             NOT NULL,
    [AccessTokenType]                       INT             NOT NULL,
    [EnableLocalLogin]                      BIT             NOT NULL,
    [IncludeJwtId]                          BIT             NOT NULL,
    [AlwaysSendClientClaims]                BIT             NOT NULL,
    [ClientClaimsPrefix]                    NVARCHAR (200)  NULL,
    [PairWiseSubjectSalt]                   NVARCHAR (200)  NULL,
    [InitiateLoginUri]                      NVARCHAR (2000) NULL,
    [UserSsoLifetime]                       INT             NULL,
    [UserCodeType]                          NVARCHAR (100)  NULL,
    [DeviceCodeLifetime]                    INT             NOT NULL,
    [CibaLifetime]                          INT             NULL,
    [PollingInterval]                       INT             NULL,
    [CoordinateLifetimeWithUserSession]     BIT             NULL,
    [Created]                               DATETIME2 (7)   NOT NULL,
    [Updated]                               DATETIME2 (7)   NULL,
    [LastAccessed]                          DATETIME2 (7)   NULL,
    [NonEditable]                           BIT             NOT NULL,
    [PushedAuthorizationLifetime]           INT             NULL,
    [RequirePushedAuthorization]            BIT             NOT NULL,
    [Discriminator]                         NVARCHAR (13)   NOT NULL,
    [SystemPermissionEnvironmentId]         INT             NULL,
    [CreatedBy]                             NVARCHAR (512)  NULL, 
    [UpdatedBy]                             NVARCHAR (512)  NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_Clients_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_Clients_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_Clients] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_Clients_SystemPermissionEnvironments_SystemPermissionEnvironmentId] FOREIGN KEY ([SystemPermissionEnvironmentId]) REFERENCES [dbo].[SystemPermissionEnvironments] ([Id])
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientsHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_Clients_ClientId]
    ON [dbo].[Clients]([ClientId] ASC);


GO
CREATE NONCLUSTERED INDEX [IX_Clients_SystemPermissionEnvironmentId]
    ON [dbo].[Clients]([SystemPermissionEnvironmentId] ASC);

