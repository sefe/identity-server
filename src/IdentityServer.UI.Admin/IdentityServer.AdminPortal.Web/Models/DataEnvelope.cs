// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Telerik.DataSource;

namespace IdentityServer.AdminPortal.Web.Models;

/// <summary>
/// An evenlope for the DataSourceResult serialization back to the client.
/// Needed because the framework cannot otherwise deserialize the IEnumerable collection
/// that the Telerik DataSource package produces - it requires an explicit type -
/// System.Text.Json cannot successfully deserialize interface properties.
/// </summary>
/// <typeparam name="T">The model type that is sent from the server</typeparam>
public class DataEnvelope<T>
{
    /// <summary>
    /// Use this when there is data grouping
    /// </summary>
    public List<AggregateFunctionsGroup> GroupedData { get; set; } = new();

    /// <summary>
    /// Use this when there is no data grouping and the response is flat data, like in the common case.
    /// </summary>
    public List<T> CurrentPageData { get; set; } = new();

    /// <summary>
    /// Always set this to the total number of records.
    /// </summary>
    public int TotalItemCount { get; set; }
}
