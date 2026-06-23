-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ClientClaims] (
    [Id]       INT            IDENTITY (1, 1) NOT NULL,
    [Type]     NVARCHAR (250) NOT NULL,
    [Value]    NVARCHAR (250) NOT NULL,
    [ClientId] INT            NOT NULL,
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientClaims_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientClaims_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ClientClaims] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ClientClaims_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientClaimsHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientClaims_ClientId_Type_Value]
    ON [dbo].[ClientClaims]([ClientId] ASC, [Type] ASC, [Value] ASC);

