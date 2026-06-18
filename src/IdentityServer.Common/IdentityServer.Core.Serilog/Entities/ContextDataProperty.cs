namespace IdentityServer.Core.Serilog.Entities;
public class ContextDataProperty<T>
{
    public required string Name { get; set; }

    public T? Value { get; set; }
}
