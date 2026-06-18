namespace IdentityServer.Abstraction.Contracts;

/// <summary>
/// Represents audit information describing when an entity was last modified and the reason.
/// </summary>
public class EntityLastModifiedData
{
    /// <summary>
    /// Entity identifier.
    /// </summary>
    public int Id { get; set; }

    /// <summary>
    /// Last modification UTC timestamp.
    /// </summary>
    public DateTime LastModified { get; set; }

    /// <summary>
    /// Reason or aspect that was modified (may be empty if not supplied).
    /// </summary>
    public string? Reason { get; set; }
}