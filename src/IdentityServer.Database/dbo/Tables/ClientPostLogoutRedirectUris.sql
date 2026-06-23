-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ClientPostLogoutRedirectUris] (
    [Id]                    INT            IDENTITY (1, 1) NOT NULL,
    [PostLogoutRedirectUri] NVARCHAR (400) NOT NULL,
    [ClientId]              INT            NOT NULL,
    [Created]               DATETIME2 (7)  NULL,
    [Updated]               DATETIME2 (7)  NULL,
    [CreatedBy]             NVARCHAR (512) NULL,
    [UpdatedBy]             NVARCHAR (512) NULL, 
    [Discriminator]         NVARCHAR (30)  DEFAULT ('ClientPostLogoutRedirectUriExt') NOT NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientPostLogoutRedirectUriss_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientPostLogoutRedirectUris_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ClientPostLogoutRedirectUris] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ClientPostLogoutRedirectUris_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientPostLogoutRedirectUrisHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientPostLogoutRedirectUris_ClientId_PostLogoutRedirectUri]
    ON [dbo].[ClientPostLogoutRedirectUris]([ClientId] ASC, [PostLogoutRedirectUri] ASC);

