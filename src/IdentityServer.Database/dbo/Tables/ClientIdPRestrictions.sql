CREATE TABLE [dbo].[ClientIdPRestrictions] (
    [Id]       INT            IDENTITY (1, 1) NOT NULL,
    [Provider] NVARCHAR (200) NOT NULL,
    [ClientId] INT            NOT NULL,
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientIdPRestrictions_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientIdPRestrictions_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ClientIdPRestrictions] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ClientIdPRestrictions_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientIdPRestrictionsHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientIdPRestrictions_ClientId_Provider]
    ON [dbo].[ClientIdPRestrictions]([ClientId] ASC, [Provider] ASC);

