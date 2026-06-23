-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE TABLE [dbo].[ApiResourceClaims] (
    [Id]            INT            IDENTITY (1, 1) NOT NULL,
    [ApiResourceId] INT            NOT NULL,
    [Type]          NVARCHAR (200) NOT NULL,
    [ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL CONSTRAINT DF_ApiResourceClaims_ValidFrom DEFAULT CONVERT(DATETIME2, '2025-01-01 00:00:00.0000000'),
    [ValidTo]   [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL CONSTRAINT DF_ApiResourceClaims_ValidTo DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo]),
    CONSTRAINT [PK_ApiResourceClaims] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_ApiResourceClaims_ApiResources_ApiResourceId] FOREIGN KEY ([ApiResourceId]) REFERENCES [dbo].[ApiResources] ([Id]) ON DELETE CASCADE
)
WITH
(
SYSTEM_VERSIONING = ON (HISTORY_TABLE = [dbo].[ApiResourceClaimsHistory])
);
GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ApiResourceClaims_ApiResourceId_Type]
    ON [dbo].[ApiResourceClaims]([ApiResourceId] ASC, [Type] ASC);

