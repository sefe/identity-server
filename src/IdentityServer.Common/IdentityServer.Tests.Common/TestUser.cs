using System.Security.Claims;
using IdentityServer.Abstraction;

namespace IdentityServer.Tests.Common;

public static class TestUserNames
{
    public const string SuperUser = "SuperUser";
    public const string Reader = "Reader";
    public const string Contributor = "Contributor";
    public const string Contributor2 = "Contributor2";
    public const string Admin = "Admin";
}

public static class TestUser
{
    public static ClaimsPrincipal SuperUser => _principals[TestUserNames.SuperUser];
    public static ClaimsPrincipal Reader => _principals[TestUserNames.Reader];
    public static ClaimsPrincipal Contributor => _principals[TestUserNames.Contributor];
    public static ClaimsPrincipal Contributor2 => _principals[TestUserNames.Contributor2];
    public static ClaimsPrincipal Admin => _principals[TestUserNames.Admin];

    public static ClaimsPrincipal Get(string name) => _principals[name];

    private static readonly Dictionary<string, ClaimsPrincipal> _principals = new()
    {
        {TestUserNames.SuperUser, CreateClaimsPrincipal(TestUserNames.SuperUser, "007",
            Constants.RoleNames.Reader, Constants.RoleNames.User, Constants.RoleNames.Admin)},
        {TestUserNames.Reader, CreateClaimsPrincipal(TestUserNames.Reader, "001", Constants.RoleNames.Reader) },
        {TestUserNames.Contributor, CreateClaimsPrincipal(TestUserNames.Contributor, "002", Constants.RoleNames.Reader, Constants.RoleNames.User) },
        {TestUserNames.Contributor2, CreateClaimsPrincipal(TestUserNames.Contributor2, "005", Constants.RoleNames.Reader, Constants.RoleNames.User) },
        {TestUserNames.Admin, CreateClaimsPrincipal(TestUserNames.Admin, "004", Constants.RoleNames.Reader, Constants.RoleNames.Admin)},
    };

    public static ClaimsPrincipal CreateClaimsPrincipal(string name, string userObjectId, params string[] roles)
    {
        var claims = new List<Claim>() {
            new("name", name),
            new("oid", userObjectId),
        };

        foreach (var role in roles)
        {
            claims.Add(new Claim("role", role));
        }

        var identity = new ClaimsIdentity(claims, "TestAuthType", "name", "role");
        var claimsPrincipal = new ClaimsPrincipal(identity);
        return claimsPrincipal;
    }
}
