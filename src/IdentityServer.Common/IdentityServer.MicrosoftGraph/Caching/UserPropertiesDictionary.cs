
namespace IdentityServer.MicrosoftGraph.Caching;

/// <summary>
/// Wrapper to cache the user profile properties (value) of the specific user ID (key).
/// </summary>
public class UserPropertiesDictionary : Dictionary<string, string>
{
    public UserPropertiesDictionary()
    {
    }

    public UserPropertiesDictionary(IDictionary<string, string> dictionary) : base(dictionary)
    {
    }
}
