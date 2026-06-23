-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

PRINT 'Running script to add scope ''identityserver.clients.read''...'

UPDATE [dbo].[ApiScopes] 
SET [ShowInDiscoveryDocument] = 0 
WHERE [ShowInDiscoveryDocument] = 1

IF (NOT EXISTS (SELECT 1 FROM [dbo].[ApiScopes] WHERE [Name] = 'identityserver.clients.read'))
BEGIN
    INSERT INTO [dbo].[ApiScopes]
               ([Enabled]
               ,[Name]
               ,[DisplayName]
               ,[Description]
               ,[Required]
               ,[Emphasize]
               ,[ShowInDiscoveryDocument]
               ,[Created]
               ,[Updated]
               ,[LastAccessed]
               ,[NonEditable])
         VALUES
               (1
               ,'identityserver.clients.read'
               ,'Read access to Clients API'
               ,'Designed for client credentials flow'
               ,0
               ,0
               ,0
               ,SYSUTCDATETIME()
               ,NULL
               ,NULL
               ,0)
END

IF (NOT EXISTS (SELECT 1 FROM [dbo].[ApiResourceScopes] WHERE [Scope] = 'identityserver.clients.read'))
BEGIN
    INSERT INTO [dbo].[ApiResourceScopes] ([Scope], [ApiResourceId])
            VALUES ('identityserver.clients.read'
                ,(SELECT Id FROM [dbo].[ApiResources] WHERE [Name] = 'identityserver'))
END


PRINT 'Running script to add scope ''identityserver.clients.read''...Finished'
