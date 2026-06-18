using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.History;

namespace IdentityServer.Data.Services;

public interface IHistoryService
{
    /// <summary>
    /// Process versions of a particular role mapping.
    /// Yields Created and Deleted events since no updates is possible for a mapping object.
    /// </summary>
    /// <typeparam name="TMapping">The type of the role mapping entity being processed.</typeparam>
    /// <param name="allVersions">A list of all temporal versions of the role mapping.</param>
    /// <param name="roleNameLookup">A dictionary mapping role IDs to their corresponding role names.</param>
    /// <param name="getRoleId">A function to extract the role ID from a mapping entity.</param>
    /// <param name="getMappingType">A function to extract the mapping type from a mapping entity.</param>
    /// <param name="getValue">A function to extract the value from a mapping entity.</param>
    /// <param name="getDescription">A function to extract the description from a mapping entity. Can return <see langword="null"/>.</param>
    /// <returns>A list of <see cref="HistoryEntryDto"/> objects representing Created and Deleted events for the role mapping.</returns>
    List<HistoryEntryDto> ProcessRoleMappingVersions<TMapping>(
        List<TMapping> allVersions,
        Dictionary<int, string> roleNameLookup,
        Func<TMapping, int> getRoleId,
        Func<TMapping, string> getMappingType,
        Func<TMapping, string> getValue,
        Func<TMapping, string?> getDescription)
        where TMapping : class, IHasId<int>, IHasPeriodData, IHasCreatedInfo, IHasUpdatedInfo;

    /// <summary>
    /// Process all versions of an entity by comparing values of specified fields.
    /// Yields Created, Updated and Deleted events.
    /// </summary>
    /// <typeparam name="TEntity">The type of the entity being tracked for changes.</typeparam>
    /// <param name="allVersions">A list of all temporal versions of the entity.</param>
    /// <param name="fieldsToCompare">An array of field names to compare between versions to detect changes.</param>
    /// <param name="entityType">A string identifier for the type of entity being tracked (e.g., "User", "Role").</param>
    /// <param name="getIdentifier">A function to extract a unique identifier or name from the entity.</param>
    /// <param name="withDeleteEventDetailed">If <see langword="true"/>, includes detailed field values in the delete event; otherwise, creates a simple delete event.</param>
    /// <returns>A list of <see cref="HistoryEntryDto"/> objects representing Created, Updated, and Deleted events for the entity.</returns>
    List<HistoryEntryDto> TrackVersionChanges<TEntity>(
        List<TEntity> allVersions,
        string[] fieldsToCompare,
        Func<TEntity, string> getIdentifier,
        bool withDeleteEventDetailed = false)
        where TEntity : class, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData;

    /// <summary>
    /// Process versions of entities that can only be added and removed.
    /// Yields single Created and Deleted events for the entity.
    /// </summary>
    /// <typeparam name="TEntity">The type of the entity that supports only add/remove operations.</typeparam>
    /// <param name="allVersions">A list of all temporal versions of the entity.</param>
    /// <param name="entityType">A string identifier for the type of entity being processed (e.g., "Claim", "Permission").</param>
    /// <param name="getIdentifier">A function to extract a unique identifier or name from the entity.</param>
    /// <param name="getCreationFields">An optional function to extract field values to include in the creation event. Can be <see langword="null"/>.</param>
    /// <returns>A list of <see cref="HistoryEntryDto"/> objects representing Created and Deleted events for the entity.</returns>
    List<HistoryEntryDto> ProcessAddRemoveEntityVersions<TEntity>(
        List<TEntity> allVersions,
        Func<TEntity, string> getIdentifier,
        Func<TEntity, List<FieldChangeDto>>? getCreationFields)
        where TEntity : class, IHasId<int>, IHasPeriodData, IHasCreatedInfo, IHasUpdatedInfo;

    /// <summary>
    /// Compares the specified fields of two entities and returns a list of changes.
    /// </summary>
    /// <typeparam name="T">The type of the entities being compared. Must be a reference type.</typeparam>
    /// <param name="oldEntity">The original entity to compare. Can be <see langword="null"/> if no prior state exists.</param>
    /// <param name="newEntity">The updated entity to compare. Cannot be <see langword="null"/>.</param>
    /// <param name="fieldsToCompare">A collection of field names to compare between the entities. Cannot be <see langword="null"/> or empty.</param>
    /// <returns>A list of <see cref="FieldChangeDto"/> objects representing the differences between the specified fields  of the
    /// two entities. The list will be empty if no changes are detected.</returns>
    List<FieldChangeDto> GetFieldChanges<T>(
        T? oldEntity,
        T newEntity,
        IEnumerable<string> fieldsToCompare) where T : class;

    /// <summary>
    /// Creates <see cref="FieldChangeDto"/> objects with values of the specified fields.
    /// </summary>
    /// <typeparam name="T">The type of the entity. Must be a reference type.</typeparam>
    /// <param name="entity">The entity from which to extract field values.</param>
    /// <param name="fieldsToCompare">A collection of field names to extract from the entity.</param>
    /// <param name="forDeletion">If <see langword="true"/>, formats the field changes for a deletion event; otherwise, for a creation or update event.</param>
    /// <returns>A list of <see cref="FieldChangeDto"/> objects containing the field names and their current values from the entity.</returns>
    List<FieldChangeDto> GetEntityFields<T>(
        T entity,
        IEnumerable<string> fieldsToCompare,
        bool forDeletion = false) where T : class;
}
