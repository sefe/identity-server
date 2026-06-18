CREATE TABLE [dbo].[ApiResourceRoles] (
    [Id]            INT            IDENTITY (1, 1) NOT NULL,
    [ApiResourceId] INT            NOT NULL,
    [RoleName]      NVARCHAR (100) NOT NULL,
    [Created]       DATETIME2 (7)  NOT NULL,
    [Updated]       DATETIME2 (7)  NULL,
    [CreatedBy]     NVARCHAR (512) NULL,
    [UpdatedBy]     NVARCHAR (512) NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ApiResourceRoles_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ApiResourceRoles_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ApiResourceRoles] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ApiResourceRoles_ApiResources_ApiResourceId] FOREIGN KEY ([ApiResourceId]) REFERENCES [dbo].[ApiResources] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ApiResourceRolesHistory])
);


GO
CREATE NONCLUSTERED INDEX [IX_ApiResourceRoles_ApiResourceId]
    ON [dbo].[ApiResourceRoles]([ApiResourceId] ASC);

GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ApiResourceRoles_ApiResourceId_RoleName]
    ON [dbo].[ApiResourceRoles]([ApiResourceId] ASC, [RoleName] ASC);