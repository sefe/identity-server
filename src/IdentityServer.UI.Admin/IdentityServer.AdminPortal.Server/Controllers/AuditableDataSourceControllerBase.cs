using Microsoft.AspNetCore.Mvc;
using Telerik.DataSource;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.AdminPortal.Web.Models;

namespace IdentityServer.AdminPortal.Server.Controllers;

public abstract class AuditableDataSourceControllerBase<T> : DataSourceControllerBase<T> where T : IHasId<int>
{
    private readonly IAuditService _auditService;

    protected AuditableDataSourceControllerBase(IAuditService auditService, ILogger logger)
        : base(logger)
    {
        _auditService = auditService;
    }

    protected override Task<ActionResult<DataEnvelope<T>>> ProcessDatasourceRequest(
        DataSourceRequest gridRequest,
        IQueryable<T> dataSource,
        List<CustomFieldFilterDefinition>? customFieldFilters,
        Func<List<T>, Task>? postProcess)
    {
        if (!typeof(IHasUpdatedInfo).IsAssignableFrom(typeof(T)))
        {
            return base.ProcessDatasourceRequest(gridRequest, dataSource, customFieldFilters, postProcess);
        }

        return base.ProcessDatasourceRequest(gridRequest, dataSource, customFieldFilters, async result =>
        {
            if (postProcess != null)
            {
                await postProcess(result);
            }
            await AddAuditTimestampsAsync(result);
        });
    }

    /// <summary>
    /// Add audit timestamps.
    /// </summary>
    protected async Task AddAuditTimestampsAsync(List<T> result)
    {
        if (result == null || result.Count == 0)
        {
            return;
        }

        var entityIds = result.Select(item => item.Id).ToList();
        var auditData = await _auditService.GetLastModifiedByIdAsync(entityIds);

        foreach (var item in result)
        {
            if (auditData.TryGetValue(item.Id, out var lastModified))
            {
                ((IHasUpdatedInfo)item).Updated = lastModified.LastModified;
            }
        }
    }
}
