using AutoMapper;
using Duende.IdentityServer.EntityFramework.Entities;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Test.Data;

namespace IdentityServer.Data.Test.Integration;

public class WhenMappingApiResources : TestBase<IMapper>
{
    ApiResource _testDataEntity;

    protected override void Given()
    {
        RecordExceptions();
        _testDataEntity = DummyClients.FetchApiResourceEntity("identityserver.api.test");
    }

    protected override IMapper CreateSystemUnderTest()
    {
        return IoC.Resolve<IMapper>(_ => { });
    }


    protected override void When()
    {
        var apiResourceEntityExt = SystemUnderTest.Map<ApiResourceExt>(_testDataEntity);
        var apiResourceModel = SystemUnderTest.Map<ApiResource>(apiResourceEntityExt);
        var apiResourceDataEntity = SystemUnderTest.Map<ApiResourceExt>(apiResourceModel);
    }

    [Test]
    public void NoExceptionsAreThrown()
    {
        Assert.That(RecordedException, Is.Null);
    }
}
