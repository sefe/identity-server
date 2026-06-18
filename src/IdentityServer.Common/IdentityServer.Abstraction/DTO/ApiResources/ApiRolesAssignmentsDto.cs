namespace IdentityServer.Abstraction.DTO.ApiResources;

public class ApiRolesAssignmentsDto
{
    public required string ApiResourceName { get; set; }
    public required Dictionary<string, List<ApiRolesPrincipalDto>> Assignments { get; set; }
}
