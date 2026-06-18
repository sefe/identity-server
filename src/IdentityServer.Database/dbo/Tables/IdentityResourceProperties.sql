CREATE TABLE [dbo].[IdentityResourceProperties] (
    [Id]                 INT             IDENTITY (1, 1) NOT NULL,
    [IdentityResourceId] INT             NOT NULL,
    [Key]                NVARCHAR (250)  NOT NULL,
    [Value]              NVARCHAR (2000) NOT NULL,
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_IdentityResourceProperties_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_IdentityResourceProperties_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_IdentityResourceProperties] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_IdentityResourceProperties_IdentityResources_IdentityResourceId] FOREIGN KEY ([IdentityResourceId]) REFERENCES [dbo].[IdentityResources] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[IdentityResourcePropertiesHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_IdentityResourceProperties_IdentityResourceId_Key]
    ON [dbo].[IdentityResourceProperties]([IdentityResourceId] ASC, [Key] ASC);

