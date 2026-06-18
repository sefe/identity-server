CREATE PROCEDURE [dbo].[GetApiResourcesLastModifiedTimestamp]
    @Ids [dbo].[IntIdList] READONLY      -- Empty = all resources, populated = specific resources
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize filter: use provided IDs or default to all resource IDs
    DECLARE @FilterIds TABLE (Id INT NOT NULL PRIMARY KEY);

    IF EXISTS (SELECT 1 FROM @Ids)
        INSERT INTO @FilterIds (Id) SELECT Id FROM @Ids;
    ELSE
        INSERT INTO @FilterIds (Id) SELECT Id FROM dbo.ApiResources;

    -- Single unified query for all cases
    WITH AllTimestamps AS (
        -- ApiResources base timestamps
        SELECT 
            ar.Id AS ApiResourceId,
            ar.Updated AS LastModified,
            'Api Resource' AS SourceTable
        FROM dbo.ApiResources ar
        INNER JOIN @FilterIds f ON ar.Id = f.Id

        UNION ALL

        -- ApiResourceRoles - max per ApiResourceId
        SELECT 
            arr.ApiResourceId,
            MAX(COALESCE(arr.Updated, arr.Created)) AS LastModified,
            'Roles' AS SourceTable
        FROM dbo.ApiResourceRoles FOR SYSTEM_TIME ALL arr
        INNER JOIN @FilterIds f ON arr.ApiResourceId = f.Id
        GROUP BY arr.ApiResourceId

        UNION ALL

        -- RoleMappings - max per ApiResourceId
        SELECT 
            arr.ApiResourceId,
            MAX(COALESCE(rm.Updated, rm.Created)) AS LastModified,
            'Role Mappings' AS SourceTable
        FROM dbo.ApiResourceRoles arr
        INNER JOIN dbo.RoleMappings FOR SYSTEM_TIME ALL rm ON rm.ApiResourceRoleId = arr.Id
        INNER JOIN @FilterIds f ON arr.ApiResourceId = f.Id
        GROUP BY arr.ApiResourceId

        UNION ALL

        -- ApiResourceSecrets - max per ApiResourceId
        SELECT 
            ars.ApiResourceId,
            MAX(COALESCE(ars.Updated, ars.Created)) AS LastModified,
            'Secrets' AS SourceTable
        FROM dbo.ApiResourceSecrets FOR SYSTEM_TIME ALL ars
        INNER JOIN @FilterIds f ON ars.ApiResourceId = f.Id
        GROUP BY ars.ApiResourceId

        UNION ALL

        -- ApiResourceScopes - max per ApiResourceId
        SELECT 
            ars.ApiResourceId,
            MAX(COALESCE(apiScope.Updated, apiScope.Created, ars.Updated, ars.Created)) AS LastModified,
            'Scopes' AS SourceTable
        FROM dbo.ApiResourceScopes FOR SYSTEM_TIME ALL ars
        LEFT JOIN dbo.ApiScopes apiScope ON ars.Scope = apiScope.Name
        INNER JOIN @FilterIds f ON ars.ApiResourceId = f.Id
        GROUP BY ars.ApiResourceId
    ),
    RankedTimestamps AS (
        SELECT 
            ApiResourceId,
            SourceTable,
            LastModified,
            ROW_NUMBER() OVER (PARTITION BY ApiResourceId ORDER BY LastModified DESC, SourceTable) AS rn
        FROM AllTimestamps
    )
    SELECT 
        ApiResourceId AS Id,
        SourceTable AS Reason,
        LastModified
    FROM RankedTimestamps
    WHERE rn = 1 AND LastModified IS NOT NULL
    ORDER BY ApiResourceId;
END;
