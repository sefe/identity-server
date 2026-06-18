CREATE PROCEDURE [dbo].[GetSystemPermissionsLastModifiedTimestamp]
    @Ids [dbo].[IntIdList] READONLY      -- Empty = all permissions, populated = specific permissions
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize filter: use provided IDs or default to all permission IDs
    DECLARE @FilterIds TABLE (Id INT NOT NULL PRIMARY KEY);

    IF EXISTS (SELECT 1 FROM @Ids)
        INSERT INTO @FilterIds (Id) SELECT Id FROM @Ids;
    ELSE
        INSERT INTO @FilterIds (Id) SELECT Id FROM dbo.SystemPermissions;

    -- Single unified query for all cases
    WITH AllTimestamps AS (
        -- SystemPermissions
        SELECT 
            sp.Id AS SystemPermissionId,
            sp.Updated AS LastModified,
            'System Permission' AS SourceTable
        FROM dbo.SystemPermissions sp
        INNER JOIN @FilterIds f ON sp.Id = f.Id

        UNION ALL

        -- SystemPermissionEnvironments
        SELECT 
            spe.SystemPermissionId,
            MAX(COALESCE(spe.Updated, spe.Created)) AS LastModified,
            'Environments' AS SourceTable
        FROM dbo.SystemPermissionEnvironments FOR SYSTEM_TIME ALL spe
        INNER JOIN @FilterIds f ON spe.SystemPermissionId = f.Id
        GROUP BY spe.SystemPermissionId

        UNION ALL

        -- SystemPermissionRole
        SELECT 
            parentEnv.SystemPermissionId,
            MAX(COALESCE(spr.Updated, spr.Created)) AS LastModified,
            'Roles' AS SourceTable
        FROM dbo.SystemPermissionRole FOR SYSTEM_TIME ALL spr
        INNER JOIN dbo.SystemPermissionEnvironments parentEnv 
            ON parentEnv.Id = spr.SystemPermissionEnvironmentId
        INNER JOIN @FilterIds f ON parentEnv.SystemPermissionId = f.Id
        GROUP BY parentEnv.SystemPermissionId
    ),
    RankedTimestamps AS (
        SELECT 
            SystemPermissionId,
            SourceTable,
            LastModified,
            ROW_NUMBER() OVER (PARTITION BY SystemPermissionId ORDER BY LastModified DESC, SourceTable) AS rn
        FROM AllTimestamps
    )
    SELECT 
        SystemPermissionId AS Id,
        SourceTable AS Reason,
        LastModified
    FROM RankedTimestamps
    WHERE rn = 1 AND LastModified IS NOT NULL
    ORDER BY SystemPermissionId;
END;
