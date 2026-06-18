using IdentityServer.Abstraction.DTO.ApiResources;

namespace IdentityServer.Data.Services;

public interface IReportingService
{
    Task<ApiRolesAssignmentsDto> BuildReportAsync(ApiRolesReportRequest request);
}
