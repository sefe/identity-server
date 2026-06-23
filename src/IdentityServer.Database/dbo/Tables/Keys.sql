-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[Keys] (
    [Id]                NVARCHAR (450) NOT NULL,
    [Version]           INT            NOT NULL,
    [Created]           DATETIME2 (7)  NOT NULL,
    [Use]               NVARCHAR (450) NULL,
    [Algorithm]         NVARCHAR (100) NOT NULL,
    [IsX509Certificate] BIT            NOT NULL,
    [DataProtected]     BIT            NOT NULL,
    [Data]              NVARCHAR (MAX) NOT NULL,
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_Keys_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_Keys_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_Keys] PRIMARY KEY CLUSTERED ([Id] ASC)
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[KeysHistory])
);


GO
CREATE NONCLUSTERED INDEX [IX_Keys_Use]
    ON [dbo].[Keys]([Use] ASC);

