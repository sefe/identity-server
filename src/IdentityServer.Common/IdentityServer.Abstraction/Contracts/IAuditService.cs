namespace IdentityServer.Abstraction.Contracts;

/// <summary>
/// Retrieve audit historic data about changes made to entities.
/// </summary>
public interface IAuditService
{
    /// <summary>
    /// Gets the last modified data for specific entities.
    /// </summary>
    /// <param name="entityIds">List of entity IDs.</param>
    /// <returns>Dictionary mapping entity IDs to their <see cref="EntityLastModifiedData"/> objects.</returns>
    Task<Dictionary<int, EntityLastModifiedData>> GetLastModifiedByIdAsync(List<int> entityIds);

    /// <summary>
    /// Gets the last modified data for a specific entity.
    /// </summary>
    /// <param name="entityId">The entity ID.</param>
    /// <returns><see cref="EntityLastModifiedData"/> if found; otherwise <c>null</c>.</returns>
    Task<EntityLastModifiedData?> GetLastModifiedByIdAsync(int entityId);
}

/// <summary>
/// Retrieve audit historic data about changes made to ApiResource entities.
/// </summary>
public interface IApiResourceAuditService : IAuditService
{
}

/// <summary>
/// Retrieve audit historic data about changes made to Client entities.
/// </summary>
public interface IClientAuditService : IAuditService
{
}

/// <summary>
/// Retrieve audit historic data about changes made to SystemPermission entities.
/// </summary>
public interface ISystemPermissionAuditService : IAuditService
{
}
