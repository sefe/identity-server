// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Reflection;
using Serilog.Events;
using IdentityServer.Core.Serilog.Entities;

namespace IdentityServer.Core.Serilog.Extensions;

public static class LogEventExtensions
{
    public static T GetPropertyOrDefault<T>(this LogEvent source, string key)
    {
        if (source.TryGetProperty<T>(key, out var value))
        {
            return value;
        }

        return default!;
    }

    public static bool TryGetProperty<T>(this LogEvent source, string key, out T value)
    {
        value = default!;
        if (!source.Properties.TryGetValue(key, out LogEventPropertyValue? value2) || value2 is null)
        {
            return false;
        }

        if (value2.AsObject() is T val)
        {
            value = val;
            return true;
        }

        return false;
    }

    public static bool TryGetCustomAppProperties(this LogEvent source, out IDictionary<string, dynamic> props)
    {
        var eligibleKeys = new HashSet<string>(
            source.Properties
                  .Where(kvp => !kvp.Key.StartsWith("Ctx.") && kvp.Value is not StructureValue)
                  .Select(kvp => kvp.Key)
                  .Except(KnownSerilogPropertyNames.All)
        );

        props = source.Properties
            .Where(sp => eligibleKeys.Contains(sp.Key))
            .ToDictionary(sp => sp.Key, sp => (dynamic)sp.Value.AsObject());

        return props.Count > 0;
    }

    private static readonly string[] _separator = new[] { "." };

    public static bool TryGetPropertyFromContext<T>(this LogEvent source, out ContextDataProperty<T>? value) where T : class, new()
    {
        var typeFromHandle = typeof(T);
        var keyPrefix = "Ctx." + typeFromHandle.Name + ".";
        var list = source.Properties
            .Where(x => x.Key.StartsWith(keyPrefix, StringComparison.Ordinal))
            .Select(x =>
            {
                var array = x.Key.Split(_separator, StringSplitOptions.None);
                return new
                {
                    Type = array[1],
                    Alias = array[2],
                    PropertyName = array[3],
                    Value = x.Value.AsObject()
                };
            })
            .ToList();

        if (list.Count == 0)
        {
            value = null;
            return false;
        }

        var target = new T();
        var inner = typeFromHandle
            .GetProperties()
            .Where(p => p.CanWrite)
            .ToList();

        static dynamic propertyMapper(dynamic lp, PropertyInfo pi) => new
        {
            TargetProperty = pi,
            NewValue = lp.Value
        };

        foreach (var tp in list.Join(inner, x => x.PropertyName, x => x.Name, (lp, pi) => propertyMapper(lp, pi)))
        {
            if (tp.TargetProperty.PropertyType.IsArray)
            {
                var elementType = tp.TargetProperty.PropertyType.GetElementType();
                var castMethod = typeof(Enumerable).GetMethod("Cast")?.MakeGenericMethod(elementType);
                var toArrayMethod = typeof(Enumerable).GetMethod("ToArray")?.MakeGenericMethod(elementType);
                var casted = castMethod?.Invoke(null, new[] { tp.NewValue });
                var arrayValue = toArrayMethod?.Invoke(null, new[] { casted! });
                tp.TargetProperty.SetValue(target, arrayValue);
            }
            else
            {
                tp.TargetProperty.SetValue(target, tp.NewValue);
            }
        }

        value = new ContextDataProperty<T>
        {
            Name = list[0].Alias ?? list[0].Type,
            Value = target
        };
        return true;
    }
}
