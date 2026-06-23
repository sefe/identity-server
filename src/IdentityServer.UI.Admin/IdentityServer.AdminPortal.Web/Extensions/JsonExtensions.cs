// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json;

namespace IdentityServer.AdminPortal.Web.Extensions;

public static class JsonExtensions
{
    /// https://github.com/telerik/blazor-ui/blob/master/grid/datasourcerequest-on-server/WasmApp/Shared/JsonExtensions.cs
    /// <summary>
    /// Tries to deserialize an object serialized to JSON accoring to its type. 
    /// Custom Extension method used to deserialize grouped data descriptors in this project.
    /// </summary>
    /// <typeparam name="T">Type to deserialize to</typeparam>
    /// <param name="element">The serialized object</param>
    /// <param name="options">Deserialization options. In the project this originates from - usually case-insensitive</param>
    /// <returns></returns>
    public static object? Deserialize<T>(this JsonElement element, JsonSerializerOptions options)
    {
        return JsonSerializer.Deserialize(element.GetRawText(), typeof(T), options);
    }
}
