using Elastic.CommonSchema;
using System.Runtime.Serialization;

namespace IdentityServer.Core.Serilog.Entities;
public class TradingLogEvent : Base
{
    public const string TopLevelProperty = "trading";

    [DataMember(Name = TopLevelProperty)]
    public  CustomProperties? TopLevel { get; set; }

    protected override bool TryRead(string propertyName, out Type? type)
    {
        type = null;
        if (propertyName == TopLevelProperty)
        {
            type = typeof(CustomProperties);
        }

        return type != null;
    }

    protected override bool ReceiveProperty(string propertyName, object value)
    {
        if (propertyName == TopLevelProperty)
        {
            TopLevel = value as CustomProperties;
            var customProperties = TopLevel;
            return customProperties != null;
        }

        return false;
    }

    protected override void WriteAdditionalProperties(Action<string, object> write)
    {
        // Avoid passing null to Action<string, object>
        if (TopLevel != null)
        {
            write(TopLevelProperty, TopLevel);
        }
    }
}
