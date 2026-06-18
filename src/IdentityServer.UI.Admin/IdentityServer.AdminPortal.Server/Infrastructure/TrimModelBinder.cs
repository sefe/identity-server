using System.Collections;
using System.Reflection;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using IdentityServer.Abstraction.Exceptions;

namespace IdentityServer.AdminPortal.Server.Infrastructure;

public class TrimModelBinder : IModelBinder
{
    private readonly IModelBinder _fallbackBinder;

    public TrimModelBinder(IModelBinder fallbackBinder)
    {
        _fallbackBinder = fallbackBinder;
    }

    public async Task BindModelAsync(ModelBindingContext bindingContext)
    {
        try
        {
            await _fallbackBinder.BindModelAsync(bindingContext);
        }
        catch (Exception ex)
        {
            throw new ModelBindingException("Model binding failed", ex);
        }

        if (bindingContext.Result.IsModelSet)
        {
            var model = bindingContext.Result.Model;
            if (model != null)
            {
                StringTrimmer.TrimAllStrings(model);
            }
        }
    }
}

/// <summary>
/// Trim strings in an object recursively.
/// Meant to be used for API's simple DTOs.
/// Supported scenarios: complex objects with direct or nested string properties, lists of strings, arrays of strings, dictionaries of strings or complex objects
/// Not supported: not listed collection types, dictionaries' keys, primitive types, enums.
/// </summary>
public static class StringTrimmer
{
    public static void TrimAllStrings(object obj)
    {
        if (obj == null) { return; }

        if (obj is IEnumerable)
        {
            ProcessEnumerableObject(obj);
        }
        else
        {
            ProcessComplexObject(obj);
        }
    }

    private static void ProcessComplexObject(object obj)
    {
        var type = obj.GetType();

        foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (!prop.CanRead || !prop.CanWrite)
            {
                continue;
            }

            if (HandleStringProperty(obj, prop))
            {
                continue;
            }

            if (HandleEnumerableProperty(obj, prop))
            {
                continue;
            }

            HandleComplexProperty(obj, prop);
        }
    }

    private static bool HandleStringProperty(object obj, PropertyInfo prop)
    {
        if (prop.GetValue(obj) is string value)
        {
            prop.SetValue(obj, value.Trim());
            return true;
        }
        return false;
    }

    private static bool HandleEnumerableProperty(object obj, PropertyInfo prop)
    {
        if (!typeof(IEnumerable).IsAssignableFrom(prop.PropertyType))
        {
            return false;
        }
        var value = prop.GetValue(obj);
        if (value != null)
        {
            ProcessEnumerableObject(value);
        }
        return true;
    }

    private static void HandleComplexProperty(object obj, PropertyInfo prop)
    {
        if (prop.PropertyType.IsPrimitive || prop.PropertyType.IsEnum)
        {
            return;
        }
        var nestedObj = prop.GetValue(obj);
        if (nestedObj != null)
        {
            TrimAllStrings(nestedObj);
        }
    }

    private static void ProcessEnumerableObject(object obj)
    {
        var enumerable = (IEnumerable)obj;
        var type = obj.GetType();
        if (type.IsArray && type.GetElementType() == typeof(string))
        {
            TrimStringArray(obj);
        }
        else if (type.IsGenericType)
        {
            var genericDef = type.GetGenericTypeDefinition();
            var genericArgs = type.GetGenericArguments();

            if (genericDef == typeof(List<>) && genericArgs[0] == typeof(string))
            {
                TrimStringList(obj);
            }
            else if (genericDef == typeof(Dictionary<,>))
            {
                ProcessDictionary(obj);
            }
            else
            {
                RecursivelyIterateEnumerable(enumerable);
            }
        }
        else
        {
            RecursivelyIterateEnumerable(enumerable);
        }
    }

    private static void TrimStringList(object obj)
    {
        var list = (List<string>)obj;
        for (int i = 0; i < list.Count; i++)
        {
            list[i] = list[i]?.Trim()!;
        }
    }

    private static void TrimStringArray(object obj)
    {
        var array = (string[])obj;
        for (int i = 0; i < array.Length; i++)
        {
            array[i] = array[i]?.Trim()!;
        }
    }

    private static void RecursivelyIterateEnumerable(IEnumerable enumerable)
    {
        foreach (var item in enumerable)
        {
            TrimAllStrings(item);
        }
    }

    private static void ProcessDictionary(object obj)
    {
        var dict = (IDictionary)obj;
        var keys = dict.Keys.Cast<object>().ToList();
        foreach (var key in keys)
        {
            var value = dict[key];
            if (value is string str)
            {
                dict[key] = str.Trim();
            }
            else if (value != null)
            {
                TrimAllStrings(value);
            }
        }
    }
}
