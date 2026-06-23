-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ClientRoleMappings] (
    [Id]            INT              IDENTITY(1,1) NOT NULL,
    [ClientRoleId]  INT              NOT NULL,
    [MappingType]   INT              NOT NULL,
    [Value]         NVARCHAR(250)    NOT NULL,
    [Description]   NVARCHAR(1000)   NULL,
    [Created]       DATETIME2 (7)    NULL,
    [Updated]       DATETIME2 (7)    NULL,
    [CreatedBy]     NVARCHAR (512)   NULL,
    [UpdatedBy]     NVARCHAR (512)   NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientRoleMappings_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientRoleMappings_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
 CONSTRAINT [PK_ClientRoleMappings] PRIMARY KEY CLUSTERED ([Id] ASC),
 CONSTRAINT [FK_ClientRoleMappings_ClientRoles_ClientRoleId] FOREIGN KEY ([ClientRoleId]) REFERENCES [dbo].[ClientRoles] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientRoleMappingsHistory])
);

GO
CREATE NONCLUSTERED INDEX [IX_ClientRoleMappings_ClientRoleId]
    ON [dbo].[ClientRoleMappings]([ClientRoleId] ASC);

GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientRoleMappings_ClientRoleId_MappingType_Value]
	ON [dbo].[ClientRoleMappings]([ClientRoleId] ASC, [MappingType] ASC, [Value] ASC);