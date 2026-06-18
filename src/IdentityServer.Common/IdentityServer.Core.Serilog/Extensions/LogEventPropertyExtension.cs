using Serilog.Events;

namespace IdentityServer.Core.Serilog.Extensions;

public static class LogEventPropertyExtension
{
    public static object AsObject(this LogEventPropertyValue propertyValue)
    {
        return propertyValue switch
        {
            SequenceValue sequenceValue => sequenceValue.Elements.Select(AsObject).ToArray(),
            ScalarValue scalarValue => scalarValue.Value!,
            DictionaryValue dictionaryValue => dictionaryValue.Elements.ToDictionary<KeyValuePair<ScalarValue, LogEventPropertyValue>, string, object>(
                kvp => kvp.Key.Value?.ToString() ?? string.Empty,
                kvp => kvp.Value.AsObject(),
                StringComparer.OrdinalIgnoreCase),
            StructureValue structureValue => BuildStructure(structureValue),
            _ => propertyValue
        };

        static object BuildStructure(StructureValue structureValue)
        {
            var dictionary = structureValue.Properties.ToDictionary<LogEventProperty, string, object>(
                kvp => kvp.Name,
                kvp => kvp.Value.AsObject(),
                StringComparer.OrdinalIgnoreCase);

            if (structureValue.TypeTag != null)
            {
                dictionary.Add("$type", structureValue.TypeTag);
            }

            return dictionary;
        }
    }
}
