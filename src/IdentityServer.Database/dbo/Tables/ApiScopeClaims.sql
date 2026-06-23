-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ApiScopeClaims] (
    [Id]      INT            IDENTITY (1, 1) NOT NULL,
    [ScopeId] INT            NOT NULL,
    [Type]    NVARCHAR (200) NOT NULL,
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ApiScopeClaims_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ApiScopeClaims_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ApiScopeClaims] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ApiScopeClaims_ApiScopes_ScopeId] FOREIGN KEY ([ScopeId]) REFERENCES [dbo].[ApiScopes] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ApiScopeClaimsHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ApiScopeClaims_ScopeId_Type]
    ON [dbo].[ApiScopeClaims]([ScopeId] ASC, [Type] ASC);

