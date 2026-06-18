using Microsoft.AspNetCore.Mvc.ModelBinding;
using NSubstitute;
using IdentityServer.AdminPortal.Server.Infrastructure;

namespace IdentityServer.AdminPortal.Test.Infrastructure;

public class TrimModelBinderProviderTests
{
    private class DummyModel { public string Name { get; set; } }

    [Test]
    public void GetBinder_WhenComplexTypeAndFromBody_ReturnsTrimModelBinder()
    {
        // Arrange
        var provider = new TrimModelBinderProvider();
        var metadataProvider = new EmptyModelMetadataProvider();
        var metadata = metadataProvider.GetMetadataForType(typeof(DummyModel));
        var context = new TestModelBinderProviderContext(metadata, BindingSource.Body);

        // Act
        var binder = provider.GetBinder(context);

        // Assert
        Assert.That(binder, Is.TypeOf<TrimModelBinder>());
    }

    [Test]
    public void GetBinder_WhenPrimitiveType_ReturnsNull()
    {
        // Arrange
        var provider = new TrimModelBinderProvider();
        var metadataProvider = new EmptyModelMetadataProvider();
        var metadata = metadataProvider.GetMetadataForType(typeof(string));
        var context = new TestModelBinderProviderContext(metadata, BindingSource.Body);

        // Act
        var binder = provider.GetBinder(context);

        // Assert
        Assert.That(binder, Is.Null);
    }

    // Minimal test double for ModelBinderProviderContext
    private class TestModelBinderProviderContext : ModelBinderProviderContext
    {
        private readonly ModelMetadata _metadata;
        private readonly BindingSource _bindingSource;
        private readonly IModelBinder _modelBinder = Substitute.For<IModelBinder>();
        private readonly IModelMetadataProvider _metadataProvider = Substitute.For<IModelMetadataProvider>();

        public TestModelBinderProviderContext(ModelMetadata metadata, BindingSource bindingSource)
        {
            _metadata = metadata;
            _bindingSource = bindingSource;
        }

        public override BindingInfo BindingInfo => new BindingInfo { BindingSource = _bindingSource };
        public override ModelMetadata Metadata => _metadata;
        public override IModelMetadataProvider MetadataProvider => _metadataProvider;
        public override IModelBinder CreateBinder(ModelMetadata metadata) => _modelBinder;
    }
}
