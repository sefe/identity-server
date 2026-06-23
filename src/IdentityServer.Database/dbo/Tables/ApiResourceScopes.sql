-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ApiResourceScopes] (
    [Id]            INT            IDENTITY (1, 1) NOT NULL,
    [Scope]         NVARCHAR (200) NOT NULL,
    [ApiResourceId] INT            NOT NULL,
    [Created]                      DATETIME2 (7)  NULL,
    [Updated]                      DATETIME2 (7)  NULL,
    [CreatedBy]                    NVARCHAR (512) NULL,
    [UpdatedBy]                    NVARCHAR (512) NULL, 
    [Discriminator]                NVARCHAR (20)  DEFAULT ('ApiResourceScopeExt') NOT NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ApiResourceScopes_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ApiResourceScopes_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ApiResourceScopes] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ApiResourceScopes_ApiResources_ApiResourceId] FOREIGN KEY ([ApiResourceId]) REFERENCES [dbo].[ApiResources] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ApiResourceScopesHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ApiResourceScopes_ApiResourceId_Scope]
    ON [dbo].[ApiResourceScopes]([ApiResourceId] ASC, [Scope] ASC);

