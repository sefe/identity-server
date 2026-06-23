-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ClientRoles](
    [Id]            INT            IDENTITY(1,1) NOT NULL,
    [ClientId]      INT            NOT NULL,
    [RoleName]      NVARCHAR(100)  NOT NULL,
    [Created]       DATETIME2 (7)  NOT NULL,
    [Updated]       DATETIME2 (7)  NULL,
    [CreatedBy]     NVARCHAR (512) NULL,
    [UpdatedBy]     NVARCHAR (512) NULL,  
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientRoles_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientRoles_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ClientRoles] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ClientRoles_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientRolesHistory])
);


GO
CREATE NONCLUSTERED INDEX [IX_ClientRoles_ClientId]
    ON [dbo].[ClientRoles]([ClientId] ASC);

GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientRoles_ClientId_RoleName]
	ON [dbo].[ClientRoles]([ClientId] ASC, [RoleName] ASC);