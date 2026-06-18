namespace IdentityServer.Core.Serilog.Extensions;

public static class TradingSerilogSystemContextDataExtensions
{
    public static IEnumerable<KeyValuePair<string, object>> DeconstructToContextPropertiesWithPrefix<T>(this T source, string prefix = "Ctx", string delimiter = ".", string? alias = null)
    {
        ArgumentNullException.ThrowIfNull(source);

        Type sourceType = source.GetType();
        var baseName = prefix + delimiter + sourceType.Name + delimiter;
        var aliasBase = alias != null ? baseName + alias + delimiter : baseName;

        return sourceType
            .GetProperties()
            .Select(pi => new
            {
                Name = aliasBase + pi.Name,
                Value = pi.GetValue(source)
            })
            .Where(x => x.Value is not null)
            .Select(x => new KeyValuePair<string, object>(x.Name, x.Value!));
    }
}
