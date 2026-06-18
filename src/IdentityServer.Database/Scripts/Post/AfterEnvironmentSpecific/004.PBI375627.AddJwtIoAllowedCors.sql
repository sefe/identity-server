PRINT 'Running script to add jwt.io as allowed cors value to the identityserver.admin application ...'

IF (NOT EXISTS (SELECT 1 FROM [dbo].[ClientCorsOrigins] WHERE [Origin] = 'https://www.jwt.io'))
BEGIN
    INSERT INTO [dbo].[ClientCorsOrigins] ([Origin], [ClientId])
            VALUES ('https://www.jwt.io'
                ,(SELECT Id FROM [dbo].[Clients] WHERE [ClientId] = 'identityserver.admin'))
END


PRINT 'Running script to add jwt.io as allowed cors value to the identityserver.admin application ...Finished'
