-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ApiScopes] (
    [Id]                      INT             IDENTITY (1, 1) NOT NULL,
    [Enabled]                 BIT             NOT NULL,
    [Name]                    NVARCHAR (200)  NOT NULL,
    [DisplayName]             NVARCHAR (200)  NULL,
    [Description]             NVARCHAR (1000) NULL,
    [Required]                BIT             NOT NULL,
    [Emphasize]               BIT             NOT NULL,
    [ShowInDiscoveryDocument] BIT             NOT NULL,
    [Created]                 DATETIME2 (7)   NOT NULL,
    [Updated]                 DATETIME2 (7)   NULL,
    [CreatedBy]               NVARCHAR (512)  NULL, 
    [UpdatedBy]               NVARCHAR (512)  NULL, 
    [LastAccessed]            DATETIME2 (7)   NULL,
    [NonEditable]             BIT             NOT NULL,
    [Discriminator]           NVARCHAR (21)   DEFAULT ('ApiScopeExt') NOT NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ApiScopes_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ApiScopes_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ApiScopes] PRIMARY KEY CLUSTERED ([Id] ASC)
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ApiScopesHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ApiScopes_Name]
    ON [dbo].[ApiScopes]([Name] ASC);

