-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ClientRedirectUris] (
    [Id]            INT            IDENTITY (1, 1) NOT NULL,
    [RedirectUri]   NVARCHAR (400) NOT NULL,
    [ClientId]      INT            NOT NULL,
    [Created]       DATETIME2 (7)  NULL,
    [Updated]       DATETIME2 (7)  NULL,
    [CreatedBy]     NVARCHAR (512) NULL,
    [UpdatedBy]     NVARCHAR (512) NULL, 
    [Discriminator] NVARCHAR (25)  DEFAULT ('ClientRedirectUriExt') NOT NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientRedirectUris_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientRedirectUris_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ClientRedirectUris] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ClientRedirectUris_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientRedirectUrisHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientRedirectUris_ClientId_RedirectUri]
    ON [dbo].[ClientRedirectUris]([ClientId] ASC, [RedirectUri] ASC);

