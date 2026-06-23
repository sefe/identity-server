-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

PRINT 'Running script to remove machine-specific Dpapi-encrypted keys ...'

DELETE FROM [dbo].[DataProtectionKeys]
WHERE Xml LIKE '%Microsoft.AspNetCore.DataProtection.XmlEncryption%'; -- NOSONAR S1739 Because a full table scan is intended here

PRINT 'Running script to remove machine-specific Dpapi-encrypted keys ...Finished'
