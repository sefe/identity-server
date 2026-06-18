using Telerik.DataSource;

namespace IdentityServer.AdminPortal.Server.Services.Grid;

public interface IGridRequestProcessor
{
    Task ProcessGridRequestAsync(DataSourceRequest request);
}

