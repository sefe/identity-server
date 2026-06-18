/*
Pre-deployment script to handle Preview column migration for system-versioned tables
This script only runs during deployment, not during build validation
*/

-- This script is designed to run only during actual deployment
-- The DACPAC deployment engine will handle the Preview column addition

:setvar __IsSqlCmdEnabled "True"
GO
IF N'$(__IsSqlCmdEnabled)' <> N'True'
    BEGIN
        PRINT N'SQLCMD mode must be enabled to successfully execute this script.';
        SET NOEXEC ON;
    END
GO

-- Handle ClientSecrets
IF EXISTS (
    SELECT 1 
    FROM sys.tables t
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    WHERE t.name = 'ClientSecrets' 
    AND t.temporal_type = 2
    AND c.name = 'Preview'
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns c
        INNER JOIN sys.tables t ON c.object_id = t.object_id
        WHERE t.name = 'ClientSecretsHistory' 
        AND c.name = 'Preview'
    )
    BEGIN
        PRINT 'Adding Preview column to ClientSecretsHistory table...'
        
        ALTER TABLE [dbo].[ClientSecrets] SET (SYSTEM_VERSIONING = OFF);
        
        ALTER TABLE [dbo].[ClientSecretsHistory] 
        ADD [Preview] NVARCHAR(50) NULL;
        
        ALTER TABLE [dbo].[ClientSecrets] SET (
            SYSTEM_VERSIONING = ON (
                HISTORY_TABLE = [dbo].[ClientSecretsHistory],
                DATA_CONSISTENCY_CHECK = ON
            )
        );
        
        PRINT 'Preview column added to ClientSecretsHistory successfully.'
    END
    ELSE
    BEGIN
        PRINT 'Preview column already exists in ClientSecretsHistory.'
    END
END
GO

-- Handle ApiResourceSecrets
IF EXISTS (
    SELECT 1 
    FROM sys.tables t
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    WHERE t.name = 'ApiResourceSecrets' 
    AND t.temporal_type = 2
    AND c.name = 'Preview'
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns c
        INNER JOIN sys.tables t ON c.object_id = t.object_id
        WHERE t.name = 'ApiResourceSecretsHistory' 
        AND c.name = 'Preview'
    )
    BEGIN
        PRINT 'Adding Preview column to ApiResourceSecretsHistory table...'
        
        ALTER TABLE [dbo].[ApiResourceSecrets] SET (SYSTEM_VERSIONING = OFF);
        
        ALTER TABLE [dbo].[ApiResourceSecretsHistory] 
        ADD [Preview] NVARCHAR(50) NULL;
        
        ALTER TABLE [dbo].[ApiResourceSecrets] SET (
            SYSTEM_VERSIONING = ON (
                HISTORY_TABLE = [dbo].[ApiResourceSecretsHistory],
                DATA_CONSISTENCY_CHECK = ON
            )
        );
        
        PRINT 'Preview column added to ApiResourceSecretsHistory successfully.'
    END
    ELSE
    BEGIN
        PRINT 'Preview column already exists in ApiResourceSecretsHistory.'
    END
END
GO