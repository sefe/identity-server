using System.Text.Json;
using Telerik.DataSource;

namespace IdentityServer.AdminPortal.Web.Extensions;

public static class GroupDataHelpers
{
    private static readonly JsonSerializerOptions _jsonSerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    /// <summary>
    /// Used to deserialize the grouped data descriptor in this sample.
    /// </summary>
    public static List<AggregateFunctionsGroup> DeserializeGroups<TGroupItem>(List<AggregateFunctionsGroup> groups)
    {
        if (groups != null)
        {
            for (int i = 0; i < groups.Count; i++)
            {
                var group = groups[i];
                var groupItems = group.Items.Cast<JsonElement>().ToList();

                if (group.HasSubgroups)
                {
                    var deserializedItems = groupItems
                        .Select(x => x.Deserialize<AggregateFunctionsGroup>(_jsonSerializerOptions))
                        .ToList();

                    var items = deserializedItems.Cast<AggregateFunctionsGroup>().ToList();
                    var subgroups = DeserializeGroups<TGroupItem>(items);
                    group.Items = subgroups;
                }
                else
                {
                    var deserializedItems = groupItems
                        .Select(x => x.Deserialize<TGroupItem>(_jsonSerializerOptions))
                        .ToList();

                    group.Items = deserializedItems;
                }
            }
        }

        return groups ?? new List<AggregateFunctionsGroup>();
    }
}
