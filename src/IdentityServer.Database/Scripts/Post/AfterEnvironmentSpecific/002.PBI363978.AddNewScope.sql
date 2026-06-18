PRINT 'Running script to add scope ''identityserver.reports.read''...'

IF (NOT EXISTS (SELECT 1 FROM [dbo].[ApiScopes] WHERE [Name] = 'identityserver.reports.read'))
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
           ,'identityserver.reports.read'
           ,'Read access to Reports API'
           ,'Designed for client credentials flow'
           ,0
           ,0
           ,0
           ,SYSUTCDATETIME()
           ,null
           ,null
           ,0)
END


IF (NOT EXISTS (SELECT 1 FROM [dbo].[ApiResourceScopes] WHERE [Scope] = 'identityserver.reports.read'))
BEGIN
    INSERT INTO [dbo].[ApiResourceScopes]
           ([Scope]
           ,[ApiResourceId])
     VALUES
           ('identityserver.reports.read'
           ,(SELECT Id FROM [dbo].[ApiResources] WHERE [Name] = 'identityserver'))
END


PRINT 'Running script to add scope ''identityserver.reports.read''...Finished'
