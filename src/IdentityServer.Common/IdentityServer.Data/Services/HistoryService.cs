using System.Collections.Concurrent;
using System.Reflection;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Attributes;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.History;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Abstraction.Enums;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.Services;

public class HistoryService : IHistoryService
{
    private static readonly ConcurrentDictionary<Type, Dictionary<string, (PropertyInfo Property, string DisplayName)>> _propertyCache = new();

    public List<HistoryEntryDto> TrackVersionChanges<TEntity>(
        List<TEntity> allVersions,
        string[] fieldsToCompare,
        Func<TEntity, string> getIdentifier,
        bool withDeleteEventDetailed = false)
        where TEntity : class, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData
    {
        var events = new List<HistoryEntryDto>();

        if (allVersions.Count == 0)
        {
            return events;
        }

        ProcessVersionHistory(allVersions, fieldsToCompare, getIdentifier, events, withDeleteEventDetailed);

        return events;
    }

    private void ProcessVersionHistory<TEntity>(List<TEntity> allVersions, string[] fieldsToCompare, Func<TEntity, string> getIdentifier, List<HistoryEntryDto> events, bool withDeleteEventDetailed = false)
        where TEntity : class, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData
    {
        // Created + Updated events:
        for (int i = 0; i < allVersions.Count; i++)
        {
            var current = allVersions[i];
            var previous = i > 0 ? allVersions[i - 1] : null;
            var isCreation = i == 0;

            var historyEntry = CreateHistoryEntry(current, previous, isCreation, fieldsToCompare, getIdentifier);

            if (historyEntry != null)
            {
                events.Add(historyEntry);
            }
        }

        // Deleted event:
        var lastVersion = allVersions[^1];
        if (lastVersion.ValidTo < DateTime.MaxValue)
        {
            events.Add(new HistoryEntryDto
            {
                Timestamp = lastVersion.ValidTo,
                EventType = HistoryEventType.Deleted,
                EntityType = MapEntityType<TEntity>(),
                EntityIdentifier = getIdentifier(lastVersion),
                ChangedBy = lastVersion.UpdatedBy,
                Changes = withDeleteEventDetailed ? GetEntityFields(lastVersion, fieldsToCompare, true) : new()
            });
        }
    }

    private HistoryEntryDto? CreateHistoryEntry<TEntity>(
        TEntity current,
        TEntity? previous,
        bool isCreation,
        string[] fieldsToCompare,
        Func<TEntity, string> getIdentifier)
        where TEntity : class, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData
    {
        var eventType = isCreation ? HistoryEventType.Created : HistoryEventType.Updated;
        var changedBy = isCreation ? current.CreatedBy : current.UpdatedBy;
        var changedAt = isCreation ? CommonHelpers.GetMaxDateTime(current.ValidFrom, current.Created) : current.ValidFrom;
        var changes = isCreation
            ? GetEntityFields(current, fieldsToCompare)
            : GetFieldChanges(previous, current, fieldsToCompare);

        if (changes.Count == 0)
        {
            return null;
        }

        return new HistoryEntryDto
        {
            Timestamp = changedAt,
            EventType = eventType,
            EntityType = MapEntityType<TEntity>(),
            EntityIdentifier = getIdentifier(current),
            ChangedBy = changedBy,
            Changes = changes
        };
    }

    public List<HistoryEntryDto> ProcessAddRemoveEntityVersions<TEntity>(
        List<TEntity> allVersions,
        Func<TEntity, string> getIdentifier,
        Func<TEntity, List<FieldChangeDto>>? getCreationFields)
        where TEntity : class, IHasId<int>, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData
    {
        var events = new List<HistoryEntryDto>();
        var groupedById = allVersions.GroupBy(v => v.Id);

        foreach (var entityVersions in groupedById)
        {
            var orderedVersions = entityVersions.OrderBy(e => e.ValidFrom).ToList();
            var firstVersion = orderedVersions[0];
            var lastVersion = orderedVersions[^1];

            events.Add(new HistoryEntryDto
            {
                Timestamp = firstVersion.ValidFrom,
                EventType = HistoryEventType.Created,
                EntityType = MapEntityType<TEntity>(),
                EntityIdentifier = getIdentifier(firstVersion),
                ChangedBy = firstVersion.CreatedBy,
                Changes = getCreationFields?.Invoke(firstVersion) ?? new()
            });

            var lastStateChanges = getCreationFields?.Invoke(lastVersion);
            foreach (var item in lastStateChanges!)
            {
                item.SwapValues();
            }

            if (lastVersion.ValidTo < DateTime.MaxValue)
            {
                events.Add(new HistoryEntryDto
                {
                    Timestamp = lastVersion.ValidTo,
                    EventType = HistoryEventType.Deleted,
                    EntityType = MapEntityType<TEntity>(),
                    EntityIdentifier = getIdentifier(lastVersion),
                    ChangedBy = lastVersion.UpdatedBy,
                    Changes = lastStateChanges
                });
            }
        }

        return events;
    }

    public List<HistoryEntryDto> ProcessRoleMappingVersions<TMapping>(
        List<TMapping> allVersions,
        Dictionary<int, string> roleNameLookup,
        Func<TMapping, int> getRoleId,
        Func<TMapping, string> getMappingType,
        Func<TMapping, string> getValue,
        Func<TMapping, string?> getDescription)
        where TMapping : class, IHasId<int>, IHasPeriodData, IHasCreatedInfo, IHasUpdatedInfo
    {
        var events = new List<HistoryEntryDto>();
        var groupedById = allVersions.GroupBy(v => v.Id);

        foreach (var mappingVersions in groupedById)
        {
            var orderedVersions = mappingVersions.OrderBy(m => m.ValidFrom).ToList();
            var firstVersion = orderedVersions[0];
            var lastVersion = orderedVersions[^1];
            var roleName = roleNameLookup[getRoleId(firstVersion)];

            events.Add(CreateRoleMappingEvent(
                firstVersion,
                roleName,
                HistoryEventType.Created,
                getMappingType,
                getValue,
                getDescription));

            if (lastVersion.ValidTo < DateTime.MaxValue)
            {
                events.Add(CreateRoleMappingEvent(
                    lastVersion,
                    roleName,
                    HistoryEventType.Deleted,
                    getMappingType,
                    getValue,
                    getDescription));
            }
        }

        return events;
    }

    public List<FieldChangeDto> GetFieldChanges<T>(
        T? oldEntity,
        T newEntity,
        IEnumerable<string> fieldsToCompare) where T : class
    {
        var changes = new List<FieldChangeDto>();
        var propertyLookup = GetPropertyLookup<T>();

        foreach (var fieldName in fieldsToCompare)
        {
            if (!propertyLookup.TryGetValue(fieldName, out var propertyInfo))
            {
                continue;
            }

            var newValue = propertyInfo.Property.GetValue(newEntity);
            var oldValue = oldEntity != null ? propertyInfo.Property.GetValue(oldEntity) : null;

            if (!AreValuesEqual(oldValue, newValue))
            {
                changes.Add(new FieldChangeDto(propertyInfo.DisplayName, FormatValue(newValue), FormatValue(oldValue)));
            }
        }

        return changes;
    }

    public List<FieldChangeDto> GetEntityFields<T>(
        T entity,
        IEnumerable<string> fieldsToCompare,
        bool forDeletion = false) where T : class
    {
        var changes = new List<FieldChangeDto>();
        var propertyLookup = GetPropertyLookup<T>();

        foreach (var fieldName in fieldsToCompare)
        {
            if (!propertyLookup.TryGetValue(fieldName, out var propertyInfo))
            {
                continue;
            }

            var value = propertyInfo.Property.GetValue(entity);
            changes.Add(new FieldChangeDto(propertyInfo.DisplayName, FormatValue(value), forDeletion ? HistoryEventType.Deleted : HistoryEventType.Created));
        }

        return changes;
    }

    private static Dictionary<string, (PropertyInfo Property, string DisplayName)> GetPropertyLookup<T>() where T : class
    {
        return _propertyCache.GetOrAdd(typeof(T), type =>
        {
            return type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .ToDictionary(
                    p => p.Name,
                    p => (p, p.GetCustomAttribute<HistoryDisplayNameAttribute>()?.DisplayName ?? p.Name));
        });
    }

    private static bool AreValuesEqual(object? value1, object? value2)
    {
        if (value1 is null && value2 is null)
        {
            return true;
        }

        if (value1 is null || value2 is null)
        {
            return false;
        }

        if (value1 is DateTime d1 && value2 is DateTime d2)
        {
            return AreDateTimesEqual(d1, d2);
        }

        return value1.Equals(value2);
    }

    private static bool AreDateTimesEqual(DateTime dt1, DateTime dt2)
    {
        return Math.Abs((dt1 - dt2).TotalSeconds) < 1;
    }

    private static string FormatValue(object? value)
    {
        return value switch
        {
            null => string.Empty,
            DateTime dt => dt.ToString("O"),
            _ => value.ToString() ?? string.Empty
        };
    }

    private static HistoryEntryDto CreateRoleMappingEvent<TMapping>(
        TMapping mapping,
        string roleName,
        HistoryEventType eventType,
        Func<TMapping, string> getMappingType,
        Func<TMapping, string> getValue,
        Func<TMapping, string?> getDescription)
        where TMapping : class, IHasPeriodData, IHasCreatedInfo, IHasUpdatedInfo
    {
        var changedBy = eventType == HistoryEventType.Created ? mapping.CreatedBy : mapping.UpdatedBy;
        var changedAt = eventType == HistoryEventType.Created ? mapping.ValidFrom : mapping.ValidTo;
        var description = getDescription(mapping);

        return new HistoryEntryDto
        {
            Timestamp = changedAt,
            EventType = eventType,
            EntityType = MapEntityType<TMapping>(),
            EntityIdentifier = $"{roleName}:{description}",
            ChangedBy = changedBy,
            Changes = new()
            {
                new FieldChangeDto("MappingType", getMappingType(mapping), eventType),
                new FieldChangeDto("Value", getValue(mapping), eventType),
                new FieldChangeDto("Description", description ?? string.Empty, eventType)
            }
        };
    }

    private static readonly Dictionary<string, string> _entityTypeMapping = new()
    {
        {nameof(ClientExt), HistoryEntryDtoExtensions.KnownEntityTypes.Client },
        {nameof(ClientRole), HistoryEntryDtoExtensions.KnownEntityTypes.ClientRole },
        {nameof(ClientGrantTypeExt), HistoryEntryDtoExtensions.KnownEntityTypes.ClientGrantType },
        {nameof(ClientScopeExt), HistoryEntryDtoExtensions.KnownEntityTypes.ClientScope },
        {nameof(ClientRedirectUriExt), HistoryEntryDtoExtensions.KnownEntityTypes.ClientRedirectUri },
        {nameof(ClientRoleMapping), HistoryEntryDtoExtensions.KnownEntityTypes.ClientRoleMapping },
        {nameof(ClientPostLogoutRedirectUriExt), HistoryEntryDtoExtensions.KnownEntityTypes.ClientPostLogoutRedirectUri },
        {nameof(ClientCorsOriginExt), HistoryEntryDtoExtensions.KnownEntityTypes.ClientCorsOrigin },
        {nameof(ClientSecretExt), HistoryEntryDtoExtensions.KnownEntityTypes.ClientSecret },
        {nameof(ClientEntraApp), HistoryEntryDtoExtensions.KnownEntityTypes.ClientEntraApp },

        {nameof(ApiScopeExt), HistoryEntryDtoExtensions.KnownEntityTypes.ApiScope },
        {nameof(ApiResourceSecretExt), HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceSecret },
        {nameof(ApiResourceRole), HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRole },
        {nameof(RoleMapping), HistoryEntryDtoExtensions.KnownEntityTypes.ApiResourceRoleMapping },
        {nameof(ApiResourceExt), HistoryEntryDtoExtensions.KnownEntityTypes.ApiResource },

        {nameof(SystemPermissionRole), HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionRole },
        {nameof(SystemPermissionEnvironment), HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermissionEnvironment },
        {nameof(SystemPermission), HistoryEntryDtoExtensions.KnownEntityTypes.SystemPermission },
    };

    private static string MapEntityType<TEntity>() where TEntity : class, IHasCreatedInfo, IHasUpdatedInfo, IHasPeriodData
    {
        var entityName = typeof(TEntity).Name;
        return _entityTypeMapping.TryGetValue(entityName, out var mappedName) ? mappedName : entityName;
    }
}
