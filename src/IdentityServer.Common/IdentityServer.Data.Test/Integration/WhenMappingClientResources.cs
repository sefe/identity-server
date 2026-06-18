using AutoMapper;
using Duende.IdentityServer.EntityFramework.Entities;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Test.Data;

namespace IdentityServer.Data.Test.Integration;

[TestFixture]
public class WhenMappingClientResources : TestBase<IMapper>
{
    Duende.IdentityServer.EntityFramework.Entities.Client testDataEntity;
    static readonly string testClientName = "Identity Server Test Client";

    protected override void Given()
    {
        RecordExceptions();
        testDataEntity = DummyClients.FetchClientEntity(testClientName);
    }

    protected override IMapper CreateSystemUnderTest()
    {
        return IoC.Resolve<IMapper>(_ => { });
    }

    protected override void When()
    {
        var clientExtEntity = SystemUnderTest.Map<ClientExt>(testDataEntity);
        var clientModel = SystemUnderTest.Map<Client>(clientExtEntity);
        var clientDataEntity = SystemUnderTest.Map<ClientExt>(clientModel);
    }

    [Test]
    public void NoExceptionsAreThrown()
    {
        Assert.That(RecordedException, Is.Null);
    }
}
