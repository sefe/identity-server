CREATE TABLE [dbo].[SystemPermissionEnvironments] (
    [Id]                 INT            IDENTITY (1, 1) NOT NULL,
    [Environment]        NVARCHAR (50)  NOT NULL,
    [SystemPermissionId] INT            NOT NULL,
    [Created]            DATETIME2 (7)  NULL,
    [Updated]            DATETIME2 (7)  NULL,
    [CreatedBy]          NVARCHAR (512) NULL,
    [UpdatedBy]          NVARCHAR (512) NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_SystemPermissionEnvironments_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_SystemPermissionEnvironments_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_SystemPermissionEnvironments] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_SystemPermissionEnvironments_SystemPermissions_SystemPermissionId] FOREIGN KEY ([SystemPermissionId]) REFERENCES [dbo].[SystemPermissions] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[SystemPermissionEnvironmentsHistory])
);


GO
CREATE NONCLUSTERED INDEX [IX_SystemPermissionEnvironments_SystemPermissionId]
    ON [dbo].[SystemPermissionEnvironments]([SystemPermissionId] ASC);

GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_SystemPermissionEnvironments_SystemPermissionId_Environment]
	ON [dbo].[SystemPermissionEnvironments]([SystemPermissionId] ASC, [Environment] ASC);