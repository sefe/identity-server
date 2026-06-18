CREATE TABLE [dbo].[ClientProperties] (
    [Id]       INT             IDENTITY (1, 1) NOT NULL,
    [ClientId] INT             NOT NULL,
    [Key]      NVARCHAR (250)  NOT NULL,
    [Value]    NVARCHAR (2000) NOT NULL,
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientProperties_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientProperties_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ClientProperties] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ClientProperties_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientPropertiesHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientProperties_ClientId_Key]
    ON [dbo].[ClientProperties]([ClientId] ASC, [Key] ASC);

