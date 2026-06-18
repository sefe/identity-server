namespace IdentityServer.Abstraction.Attributes;

/// <summary>
/// Specifies a custom display name for a property when it appears in history tracking records.
/// When applied to a property, the history service will use the specified display name 
/// instead of the property's actual name in field change descriptions.
/// </summary>
[AttributeUsage(AttributeTargets.Property, Inherited = false, AllowMultiple = false)]
public sealed class HistoryDisplayNameAttribute : Attribute
{
    public string DisplayName { get; }

    /// <summary>
    /// Initializes a new instance of the <see cref="HistoryDisplayNameAttribute"/> class.
    /// </summary>
    /// <param name="displayName">The display name to use for the property in history records.</param>
    public HistoryDisplayNameAttribute(string displayName)
    {
        DisplayName = displayName;
    }
}
