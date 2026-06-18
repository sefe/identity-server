using System.Linq.Expressions;
using Microsoft.AspNetCore.Mvc;
using Telerik.DataSource;
using Telerik.DataSource.Extensions;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.AdminPortal.Server.Services.Grid;
using IdentityServer.AdminPortal.Web.Models;

namespace IdentityServer.AdminPortal.Server.Controllers;

public abstract class DataSourceControllerBase<T> : ControllerBase
{
    protected ILogger Logger;

    protected DataSourceControllerBase(ILogger logger)
    {
        Logger = logger;
    }

    private readonly DateTimeToDayRangeFilterConverter _createdRequestProcessor = new(nameof(IHasCreatedInfo.Created));

    protected virtual async Task<ActionResult<DataEnvelope<T>>> ProcessDatasourceRequest(
        DataSourceRequest gridRequest,
        IQueryable<T> dataSource,
        List<CustomFieldFilterDefinition>? customFieldFilters,
        Func<List<T>, Task>? postProcess)
    {
        try
        {
            dataSource = await ApplyPreprocessingAsync(gridRequest, dataSource, customFieldFilters);

            DataSourceResult processedData = await dataSource.ToDataSourceResultAsync(gridRequest);

            DataEnvelope<T> dataToReturn = await CreateDataEnvelopeAsync(gridRequest, processedData, postProcess);

            return Ok(dataToReturn);
        }
        catch (InvalidCastException ex)
        {
            Logger.LogWarning(ex, "The data source request likely contains an invalid filter value");
            return BadRequest();
        }
    }

    private async Task<IQueryable<T>> ApplyPreprocessingAsync(
        DataSourceRequest gridRequest,
        IQueryable<T> dataSource,
        List<CustomFieldFilterDefinition>? customFieldFilters)
    {
        if (typeof(IHasCreatedInfo).IsAssignableFrom(typeof(T)))
        {
            await _createdRequestProcessor.ProcessGridRequestAsync(gridRequest);
        }

        if (customFieldFilters == null)
        {
            return dataSource;
        }

        foreach (var customFieldFilter in customFieldFilters)
        {
            dataSource = ProcessCustomFieldFilter(gridRequest, dataSource, customFieldFilter.FieldName, customFieldFilter.FilterOperators);
        }

        return dataSource;
    }

    private static async Task<DataEnvelope<T>> CreateDataEnvelopeAsync(
        DataSourceRequest gridRequest,
        DataSourceResult processedData,
        Func<List<T>, Task>? postProcess)
    {
        if (gridRequest.Groups?.Count > 0)
        {
            return CreateGroupedDataEnvelope(processedData);
        }

        return await CreateFlatDataEnvelopeAsync(processedData, postProcess);
    }

    private static DataEnvelope<T> CreateGroupedDataEnvelope(DataSourceResult processedData)
    {
        // If there is grouping, use the field for grouped data
        // The app must be able to serialize and deserialize it
        // Example helper methods for this are available in this project
        // See the GroupDataHelper.DeserializeGroups and JsonExtensions.Deserialize methods
        return new DataEnvelope<T>
        {
            GroupedData = processedData.Data.Cast<AggregateFunctionsGroup>().ToList(),
            TotalItemCount = processedData.Total
        };
    }

    private static async Task<DataEnvelope<T>> CreateFlatDataEnvelopeAsync(
        DataSourceResult processedData,
        Func<List<T>, Task>? postProcess)
    {
        // When there is no grouping, the simplistic approach of 
        // just serializing and deserializing the flat data is enough
        var dataToReturn = new DataEnvelope<T>
        {
            CurrentPageData = processedData.Data.Cast<T>().ToList(),
            TotalItemCount = processedData.Total
        };

        if (postProcess != null)
        {
            await postProcess(dataToReturn.CurrentPageData);
        }

        return dataToReturn;
    }

    private static IQueryable<T> ProcessCustomFieldFilter(DataSourceRequest gridRequest, IQueryable<T> query, string fieldName, IReadOnlyDictionary<FilterOperator, Func<string, Expression<Func<T, bool>>>> filterOperators)
    {
        var filters = gridRequest.Filters;
        if (filters == null)
        {
            return query;
        }

        var extractedFilters = new List<FilterDescriptor>();

        FindAndRemove(fieldName, filters, extractedFilters);

        foreach (var filter in extractedFilters)
        {
            var value = filter.Value?.ToString();
            if (!string.IsNullOrEmpty(value) && filterOperators.TryGetValue(filter.Operator, out var expressionFunc))
            {
                var predicate = expressionFunc(value);
                query = query.Where(predicate);
            }
        }

        return query;
    }

    private static void FindAndRemove(string fieldName, IList<IFilterDescriptor> descriptors, List<FilterDescriptor> extracted)
    {
        for (int i = descriptors.Count - 1; i >= 0; i--)
        {
            if (descriptors[i] is FilterDescriptor fd && fd.Member == fieldName)
            {
                extracted.Add(fd);
                descriptors.RemoveAt(i);
            }
            else if (descriptors[i] is CompositeFilterDescriptor cfd)
            {
                FindAndRemove(fieldName, cfd.FilterDescriptors, extracted);
                if (cfd.FilterDescriptors.Count == 0)
                {
                    descriptors.RemoveAt(i);
                }
            }
        }
    }

    public class CustomFieldFilterDefinition
    {
        public CustomFieldFilterDefinition(string fieldName, IReadOnlyDictionary<FilterOperator, Func<string, Expression<Func<T, bool>>>> filterOperators)
        {
            FieldName = fieldName;
            FilterOperators = filterOperators;
        }

        public string FieldName { get; private set; }
        public IReadOnlyDictionary<FilterOperator, Func<string, Expression<Func<T, bool>>>> FilterOperators { get; private set; }
    }
}
