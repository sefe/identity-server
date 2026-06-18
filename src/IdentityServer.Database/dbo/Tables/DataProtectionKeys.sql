CREATE TABLE [dbo].[DataProtectionKeys] (
    [Id]           INT            IDENTITY (1, 1) NOT NULL,
    [FriendlyName] NVARCHAR (MAX) NULL,
    [Xml]          NVARCHAR (MAX) NULL,
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_DataProtectionKeys_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_DataProtectionKeys_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_DataProtectionKeys] PRIMARY KEY CLUSTERED ([Id] ASC)
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[DataProtectionKeysHistory])
);

