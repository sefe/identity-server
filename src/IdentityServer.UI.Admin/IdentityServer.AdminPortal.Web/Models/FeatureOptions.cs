namespace IdentityServer.AdminPortal.Web.Models;

public class FeatureOptions
{
    public const string Features = "Features";

    public bool FilterUserRoleOnLogin { get; set; } = false;

    /// <summary>
    /// Max limit of visible resources' writers in the UI on 'Applications' and 'Api Resources' pages.
    /// </summary>
    public int MaxVisibleResourceWriters { get; set; } = 3;
}
