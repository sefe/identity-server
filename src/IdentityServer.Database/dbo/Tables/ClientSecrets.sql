CREATE TABLE [dbo].[ClientSecrets] (
    [Id]            INT             IDENTITY (1, 1) NOT NULL,
    [ClientId]      INT             NOT NULL,
    [Description]   NVARCHAR (200)  NOT NULL,
    [Value]         NVARCHAR (4000) NOT NULL,
    [Expiration]    DATETIME2 (7)   NULL,
    [Type]          NVARCHAR (250)  NOT NULL,
    [Created]       DATETIME2 (7)   NOT NULL,
    [Updated]       DATETIME2 (7)   NULL,
    [CreatedBy]     NVARCHAR (512)  NULL,
    [UpdatedBy]     NVARCHAR (512)  NULL, 
    [Discriminator] NVARCHAR (20)   DEFAULT ('ClientSecretExt') NOT NULL,
    [Preview]       NVARCHAR(50) NULL,
    [ValidFrom]     [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientSecrets_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]       [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientSecrets_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ClientSecrets] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ClientSecrets_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientSecretsHistory])
);


GO
CREATE NONCLUSTERED INDEX [IX_ClientSecrets_ClientId]
    ON [dbo].[ClientSecrets]([ClientId] ASC);

GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientSecrets_ClientId_Type_Description]
    ON [dbo].[ClientSecrets]([ClientId] ASC, [Type] ASC, [Description] ASC);