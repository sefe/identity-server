using IdentityServer.Abstraction.DTO.History;

namespace IdentityServer.AdminPortal.Web.Services.History;

/// <summary>
/// Base interface for entity-specific history undo services.
/// </summary>
/// <typeparam name="TEntity">The parent entity type for undo operations.</typeparam>
public interface IEntityHistoryUndoService<TEntity>
{
    /// <summary>
    /// Gets the entity types this service can handle.
    /// </summary>
    IReadOnlySet<string> SupportedEntityTypes { get; }

    /// <summary>
    /// Determines if this service can handle the given entity type.
    /// </summary>
    bool CanHandle(string entityType);

    /// <summary>
    /// Determines if the given history entry can be undone.
    /// </summary>
    /// <param name="entry">The history entry to evaluate.</param>
    /// <param name="currentEntity">The current state of the parent entity.</param>
    /// <returns>Eligibility result with reason if ineligible.</returns>
    UndoEligibility CanUndo(HistoryEntryDto entry, TEntity? currentEntity);

    /// <summary>
    /// Executes the undo operation for the given history entry.
    /// </summary>
    /// <param name="entry">The history entry to undo.</param>
    /// <param name="entity">The current state of the parent entity.</param>
    /// <returns>Result of the undo operation containing the updated entity.</returns>
    Task<ApiCallResult<TEntity>> ExecuteUndoAsync(HistoryEntryDto entry, TEntity entity);
}
