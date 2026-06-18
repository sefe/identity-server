using IdentityServer.Abstraction;

namespace IdentityServer.Tests.Common;

public class MockCurrentUserService : ICurrentUserService
{
    private readonly string _username;

    public MockCurrentUserService() { }

    public MockCurrentUserService(string username)
    {
        _username = username;
    }

    public string UserName => _username  ?? "testuser";
}
