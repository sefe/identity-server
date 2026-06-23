-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ApiResources] (
    [Id]                                  INT             IDENTITY (1, 1) NOT NULL,
    [Enabled]                             BIT             NOT NULL,
    [Name]                                NVARCHAR (200)  NOT NULL,
    [DisplayName]                         NVARCHAR (200)  NULL,
    [Description]                         NVARCHAR (1000) NULL,
    [AllowedAccessTokenSigningAlgorithms] NVARCHAR (100)  NULL,
    [ShowInDiscoveryDocument]             BIT             NOT NULL,
    [RequireResourceIndicator]            BIT             NOT NULL,
    [Created]                             DATETIME2 (7)   NOT NULL,
    [Updated]                             DATETIME2 (7)   NULL,
    [LastAccessed]                        DATETIME2 (7)   NULL,
    [NonEditable]                         BIT             NOT NULL,
    [Discriminator]                       NVARCHAR (21)   NOT NULL,
    [SystemPermissionEnvironmentId]       INT             NULL,
    [CreatedBy]                           NVARCHAR (512)  NULL,
    [UpdatedBy]                           NVARCHAR (512)  NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ApiResources_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ApiResources_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ApiResources] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ApiResources_SystemPermissionEnvironments_SystemPermissionEnvironmentId] FOREIGN KEY ([SystemPermissionEnvironmentId]) REFERENCES [dbo].[SystemPermissionEnvironments] ([Id])
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ApiResourcesHistory])
);


GO
CREATE NONCLUSTERED INDEX [IX_ApiResources_SystemPermissionEnvironmentId]
    ON [dbo].[ApiResources]([SystemPermissionEnvironmentId] ASC);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ApiResources_Name]
    ON [dbo].[ApiResources]([Name] ASC);

