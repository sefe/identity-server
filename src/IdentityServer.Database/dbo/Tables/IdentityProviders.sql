-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[IdentityProviders] (
    [Id]           INT            IDENTITY (1, 1) NOT NULL,
    [Scheme]       NVARCHAR (200) NOT NULL,
    [DisplayName]  NVARCHAR (200) NULL,
    [Enabled]      BIT            NOT NULL,
    [Type]         NVARCHAR (20)  NOT NULL,
    [Properties]   NVARCHAR (MAX) NULL,
    [Created]      DATETIME2 (7)  NOT NULL,
    [Updated]      DATETIME2 (7)  NULL,
    [LastAccessed] DATETIME2 (7)  NULL,
    [NonEditable]  BIT            NOT NULL,
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_IdentityProviders_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_IdentityProviders_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_IdentityProviders] PRIMARY KEY CLUSTERED ([Id] ASC)
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[IdentityProvidersHistory])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_IdentityProviders_Scheme]
    ON [dbo].[IdentityProviders]([Scheme] ASC);

