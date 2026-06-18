using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive.Banner;

public class TestSecret : IHasExpiration
{
    public DateTime? Expiration { get; set; }
}
