using System.Collections;

namespace IdentityServer.Core.Serilog.Entities;
public class CustomProperties : IDictionary<string, object>
{
    private readonly Dictionary<string, object> _properties;

    public int Count => _properties.Count;

    public bool IsReadOnly => false;

    public object this[string key]
    {
        get
        {
            return _properties[key];
        }
        set
        {
            _properties[key] = value;
        }
    }

    public ICollection<string> Keys => _properties.Keys;

    public ICollection<object> Values => _properties.Values;

    public CustomProperties()
    {
        _properties = new Dictionary<string, object>();
    }

    public IEnumerator<KeyValuePair<string, object>> GetEnumerator()
    {
        return _properties.GetEnumerator();
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }

    public void Add(KeyValuePair<string, object> item)
    {
        _properties.Add(item.Key, item.Value);
    }

    public void Clear()
    {
        _properties.Clear();
    }

    public bool Contains(KeyValuePair<string, object> item)
    {
        return _properties.Contains(item);
    }

    public void CopyTo(KeyValuePair<string, object>[] array, int arrayIndex)
    {
        ((ICollection<KeyValuePair<string, object>>)_properties).CopyTo(array, arrayIndex);
    }

    public bool Remove(KeyValuePair<string, object> item)
    {
        return _properties.Remove(item.Key);
    }

    public void Add(string key, object value)
    {
        _properties.Add(key, value);
    }

    public bool ContainsKey(string key)
    {
        return _properties.ContainsKey(key);
    }

    public bool Remove(string key)
    {
        return _properties.Remove(key);
    }

    public bool TryGetValue(string key, out object value)
    {

        return _properties.TryGetValue(key, out value!);
    }
}
