CREATE TABLE [dbo].[ClientScopes] (
    [Id]            INT            IDENTITY (1, 1) NOT NULL,
    [Scope]         NVARCHAR (200) NOT NULL,
    [ClientId]      INT            NOT NULL,
    [Created]       DATETIME2 (7)  NULL,
    [Updated]       DATETIME2 (7)  NULL,
    [CreatedBy]     NVARCHAR (512) NULL,
    [UpdatedBy]     NVARCHAR (512) NULL, 
    [Discriminator] NVARCHAR (15)  DEFAULT ('ClientScopeExt') NOT NULL, 
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ClientScopes_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ClientScopes_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ClientScopes] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ClientScopes_Clients_ClientId] FOREIGN KEY ([ClientId]) REFERENCES [dbo].[Clients] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ClientScopesHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ClientScopes_ClientId_Scope]
    ON [dbo].[ClientScopes]([ClientId] ASC, [Scope] ASC);

