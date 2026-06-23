-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[RoleMappings] (
    [Id]                INT            IDENTITY (1, 1) NOT NULL,
    [ApiResourceRoleId] INT            NOT NULL,
    [MappingType]       INT            NOT NULL,
    [RoleMappingTypeId] INT            NOT NULL,
    [Value]             NVARCHAR (250) NOT NULL,
    [Description]       NVARCHAR (512) NULL,
    [Created]           DATETIME2 (7)  NULL,
    [Updated]           DATETIME2 (7)  NULL,
    [CreatedBy]         NVARCHAR (512) NULL,
    [UpdatedBy]         NVARCHAR (512) NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_RoleMappings_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_RoleMappings_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_RoleMappings] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_RoleMappings_ApiResourceRoles_ApiResourceRoleId] FOREIGN KEY ([ApiResourceRoleId]) REFERENCES [dbo].[ApiResourceRoles] ([Id]) ON DELETE CASCADE,
    CONSTRAINT [FK_RoleMappings_RoleMappingTypes_RoleMappingTypeId] FOREIGN KEY ([RoleMappingTypeId]) REFERENCES [dbo].[RoleMappingTypes] ([Id])
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[RoleMappingsHistory])
);


GO
CREATE NONCLUSTERED INDEX [IX_RoleMappings_RoleMappingTypeId]
    ON [dbo].[RoleMappings]([RoleMappingTypeId] ASC);


GO
CREATE NONCLUSTERED INDEX [IX_RoleMappings_ApiResourceRoleId]
    ON [dbo].[RoleMappings]([ApiResourceRoleId] ASC);

GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_RoleMappings_ApiResourceRoleId_MappingType_Value]
	ON [dbo].[RoleMappings]([ApiResourceRoleId] ASC, [MappingType] ASC, [RoleMappingTypeId] ASC, [Value] ASC);