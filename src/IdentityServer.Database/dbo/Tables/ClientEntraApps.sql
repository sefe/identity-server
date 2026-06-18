CREATE TABLE [dbo].[ClientEntraApps]
(
    [Id]            INT            IDENTITY (1, 1) NOT NULL,
    [AppId]         NVARCHAR (50)  NOT NULL,
    [AppName]       NVARCHAR (300) NOT NULL,
    [ClientId]      INT            NOT NULL,
    [Created]       DATETIME2 (7)  NULL,
    [Updated]       DATETIME2 (7)  NULL,
    [CreatedBy]     NVARCHAR (512) NULL,
    [UpdatedBy]     NVARCHAR (512) NULL,
    [ValidFrom]     [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientEntraApps_ValidFrom DEFAULT SYSUTCDATETIME(),
    [ValidTo]       [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientEntraApps_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ClientEntraApps] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ClientEntraApps_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
)
WITH
(
    SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientEntraAppsHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientEntraApps_ClientId_AppId]
    ON [dbo].[ClientEntraApps]([ClientId] ASC, [AppId] ASC);

