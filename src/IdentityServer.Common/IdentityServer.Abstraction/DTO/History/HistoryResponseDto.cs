namespace IdentityServer.Abstraction.DTO.History;

/// <summary>
/// Complete history response for an entity including all nested entities.
/// </summary>
public class HistoryResponseDto
{
    /// <summary>
    /// Gets or sets the database ID of the entity.
    /// </summary>
    public int EntityId { get; set; }

    /// <summary>
    /// Gets or sets the name of the entity.
    /// </summary>
    public required string EntityName { get; set; }

    /// <summary>
    /// Gets or sets the list of all history events for this entity and its nested entities.
    /// </summary>
    public List<HistoryEntryDto> History { get; set; } = new();
}
