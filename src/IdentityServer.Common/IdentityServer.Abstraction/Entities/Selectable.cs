namespace IdentityServer.Abstraction.Entities;

public class Selectable
{
    public bool IsSelected { get; set; }
    public required string DisplayName { get; set; }
}

public class SelectableValue<T> : Selectable
{
    public required T Value { get; set; }
}
