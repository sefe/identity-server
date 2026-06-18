using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Tests.Common.Builders;

public class ClientExtMockStorageBuilder : MockStorageBuilder<ClientExt>
{
    public ClientExtMockStorageBuilder() : base(m => m.Id)
    {
    }
    public ClientExtMockStorageBuilder WithClient(string clientId, string clientName)
    {
        var item = new ClientExt
        {
            Id = _mockStorage.Items.Count + 1,
            ClientId = clientId,
            ClientName = clientName,
            SystemPermissionEnvironment = new SystemPermissionEnvironment()
            {
                Environment = SystemPermissionEnvironmentNames.Development,
                SystemPermission = new SystemPermission
                {
                    Name = "Default System Permission",
                    Description = "Default System Permission for testing purposes"
                }
            }
        };
        WithItem(item);
        return this;
    }
}
