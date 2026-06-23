// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Collections.Concurrent;
using System.Text;

namespace IdentityServer.Abstraction.Extensions;

public static class TypeExtensions
{
    private static readonly ConcurrentDictionary<Type, string> _typeDisplayNameCache = new();

    /// <summary>
    /// Generates a string representation of the specified type, including generic type arguments if applicable.
    /// </summary>
    /// <param name="type">The <see cref="Type"/> for which to generate the name. Must not be <see langword="null"/>.</param>
    /// <returns>The name of the type. For generic types, the name includes the generic type arguments in angle brackets. For
    /// example, "List&lt;String&gt;" for a generic list of strings.</returns>
    public static string GetTypeDisplayName(this Type type)
    {
        return _typeDisplayNameCache.GetOrAdd(type, static t =>
        {
            if (!t.IsGenericType)
            {
                return t.Name;
            }

            var sb = new StringBuilder();
            BuildTypeDisplayName(t, sb);
            return sb.ToString();
        });
    }

    private static void BuildTypeDisplayName(Type type, StringBuilder sb)
    {
        if (!type.IsGenericType)
        {
            sb.Append(type.Name);
            return;
        }

        // Extract the base name without the generic arity marker (e.g., "List`1" -> "List")
        var typeName = type.Name;
        var backtickIndex = typeName.IndexOf('`');
        if (backtickIndex > 0)
        {
            sb.Append(typeName, 0, backtickIndex);
        }
        else
        {
            sb.Append(typeName);
        }

        // Append generic type arguments
        sb.Append('<');
        var genericArgs = type.GetGenericArguments();
        for (int i = 0; i < genericArgs.Length; i++)
        {
            if (i > 0)
            {
                sb.Append(',');
            }
            BuildTypeDisplayName(genericArgs[i], sb);
        }
        sb.Append('>');
    }
}
