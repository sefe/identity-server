-- Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
-- SPDX-License-Identifier: Apache-2.0

CREATE PROCEDURE [dbo].[GetClientsLastModifiedTimestamp]
    @Ids [dbo].[IntIdList] READONLY      -- Empty = all clients, populated = specific clients
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize filter: use provided IDs or default to all client IDs
    DECLARE @FilterIds TABLE (Id INT NOT NULL PRIMARY KEY);

    IF EXISTS (SELECT 1 FROM @Ids)
        INSERT INTO @FilterIds (Id) SELECT Id FROM @Ids;
    ELSE
        INSERT INTO @FilterIds (Id) SELECT Id FROM dbo.Clients;

    -- Single unified query for all cases
    WITH AllTimestamps AS (
        -- Clients base timestamps
        SELECT 
            c.Id AS ClientId,
            c.Updated AS LastModified,
            'Application' AS SourceTable
        FROM dbo.Clients c
        INNER JOIN @FilterIds f ON c.Id = f.Id

        UNION ALL

        -- ClientSecrets - max per ClientId
        SELECT 
            cs.ClientId,
            MAX(COALESCE(cs.Updated, cs.Created)) AS LastModified,
            'Secrets' AS SourceTable
        FROM dbo.ClientSecrets FOR SYSTEM_TIME ALL cs
        INNER JOIN @FilterIds f ON cs.ClientId = f.Id
        GROUP BY cs.ClientId

        UNION ALL

        -- ClientScopes - max per ClientId
        SELECT 
            cs.ClientId,
            MAX(COALESCE(cs.Updated, cs.Created)) AS LastModified,
            'Scopes' AS SourceTable
        FROM dbo.ClientScopes FOR SYSTEM_TIME ALL cs
        INNER JOIN @FilterIds f ON cs.ClientId = f.Id
        GROUP BY cs.ClientId

        UNION ALL

        -- ClientGrantTypes - max per ClientId
        SELECT 
            cgt.ClientId,
            MAX(COALESCE(cgt.Updated, cgt.Created)) AS LastModified,
            'Grants' AS SourceTable
        FROM dbo.ClientGrantTypes FOR SYSTEM_TIME ALL cgt
        INNER JOIN @FilterIds f ON cgt.ClientId = f.Id
        GROUP BY cgt.ClientId

        UNION ALL

        -- ClientRedirectUris - max per ClientId
        SELECT 
            cru.ClientId,
            MAX(COALESCE(cru.Updated, cru.Created)) AS LastModified,
            'Redirect URIs' AS SourceTable
        FROM dbo.ClientRedirectUris FOR SYSTEM_TIME ALL cru
        INNER JOIN @FilterIds f ON cru.ClientId = f.Id
        GROUP BY cru.ClientId

        UNION ALL

        -- ClientPostLogoutRedirectUris - max per ClientId
        SELECT 
            cplru.ClientId,
            MAX(COALESCE(cplru.Updated, cplru.Created)) AS LastModified,
            'Post Logout Redirect URIs' AS SourceTable
        FROM dbo.ClientPostLogoutRedirectUris FOR SYSTEM_TIME ALL cplru
        INNER JOIN @FilterIds f ON cplru.ClientId = f.Id
        GROUP BY cplru.ClientId

        UNION ALL

        -- ClientCorsOrigins - max per ClientId
        SELECT 
            cco.ClientId,
            MAX(COALESCE(cco.Updated, cco.Created)) AS LastModified,
            'CORS Origins' AS SourceTable
        FROM dbo.ClientCorsOrigins FOR SYSTEM_TIME ALL cco
        INNER JOIN @FilterIds f ON cco.ClientId = f.Id
        GROUP BY cco.ClientId

        UNION ALL

        -- ClientEntraApps - max per ClientId
        SELECT 
            cea.ClientId,
            MAX(COALESCE(cea.Updated, cea.Created)) AS LastModified,
            'Entra Apps' AS SourceTable
        FROM dbo.ClientEntraApps FOR SYSTEM_TIME ALL cea
        INNER JOIN @FilterIds f ON cea.ClientId = f.Id
        GROUP BY cea.ClientId

        UNION ALL

        -- ClientRoles - max per ClientId
        SELECT 
            cr.ClientId,
            MAX(COALESCE(cr.Updated, cr.Created)) AS LastModified,
            'Roles' AS SourceTable
        FROM dbo.ClientRoles FOR SYSTEM_TIME ALL cr
        INNER JOIN @FilterIds f ON cr.ClientId = f.Id
        GROUP BY cr.ClientId

        UNION ALL

        -- RoleMappings - max per ClientId
        SELECT 
            cr.ClientId,
            MAX(COALESCE(rm.Updated, rm.Created)) AS LastModified,
            'Role Mappings' AS SourceTable
        FROM dbo.ClientRoles cr
        INNER JOIN dbo.ClientRoleMappings FOR SYSTEM_TIME ALL rm ON rm.ClientRoleId = cr.Id
        INNER JOIN @FilterIds f ON cr.ClientId = f.Id
        GROUP BY cr.ClientId
    ),
    RankedTimestamps AS (
        SELECT 
            ClientId,
            SourceTable,
            LastModified,
            ROW_NUMBER() OVER (PARTITION BY ClientId ORDER BY LastModified DESC, SourceTable) AS rn
        FROM AllTimestamps
    )
    SELECT 
        ClientId AS Id,
        SourceTable AS Reason,
        LastModified
    FROM RankedTimestamps
    WHERE rn = 1 AND LastModified IS NOT NULL
    ORDER BY ClientId;
END;
