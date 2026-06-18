namespace IdentityServer.AdminPortal.Web.Constants;

public static class PageRoutes
{
    public const string ApiResources = "/apiresources";
    public static string ApiResourcesEdit(int apiId) => $"/apiresources/edit/{apiId}";
    public static string ApiResourcesImportRoles(int apiId) => $"/apiresources/edit/{apiId}/import/roles";
    public static string ApiResourcesClone(int apiId) => $"/apiresources/clone/{apiId}";
    public const string ApiResourcesNew = "/apiresources/new";
    public static string ApiResourceHistory(int apiResourceId) => $"/apiresources/{apiResourceId}/history";

    public const string Applications = "/applications";
    public static string ApplicationsEdit(int applicationId) => $"/applications/edit/{applicationId}";
    public static string ApplicationsImportRoles(int applicationId) => $"/applications/edit/{applicationId}/import/roles";
    public static string ApplicationsClone(int applicationId) => $"/applications/clone/{applicationId}";
    public const string ApplicationsNew = "/applications/new";
    public static string ApplicationsHistory(int applicationId) => $"/applications/{applicationId}/history";

    public const string SystemPermissions = "/systempermissions";
    public const string SystemPermissionsNew = "/systempermissions/new";
    public static string SystemPermissionsEdit(int systemPermissionId) => $"/systempermissions/edit/{systemPermissionId}";
    public static string SystemPermissionHistory(int systemPermissionId) => $"/systempermissions/{systemPermissionId}/history";
}
