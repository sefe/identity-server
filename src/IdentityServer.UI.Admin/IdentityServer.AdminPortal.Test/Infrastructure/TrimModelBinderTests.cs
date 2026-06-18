using Microsoft.AspNetCore.Mvc.ModelBinding;
using NSubstitute;
using IdentityServer.AdminPortal.Server.Infrastructure;

namespace IdentityServer.AdminPortal.Test.Infrastructure;

public class TrimModelBinderTests
{
    private class DummyModel { public string Name { get; set; } }

    private class FakeBinder : IModelBinder
    {
        private readonly object _model;
        public FakeBinder(object model) { _model = model; }
        public Task BindModelAsync(ModelBindingContext bindingContext)
        {
            bindingContext.Result = ModelBindingResult.Success(_model);
            return Task.CompletedTask;
        }
    }

    [Test]
    public async Task BindModelAsync_WhenModelIsSet_StringsAreTrimmed()
    {
        // Arrange
        var model = new DummyModel { Name = " \t test \t " };
        var binder = new TrimModelBinder(new FakeBinder(model));
        var valueProvider = Substitute.For<IValueProvider>();
        var context = new DefaultModelBindingContext
        {
            ModelMetadata = new EmptyModelMetadataProvider().GetMetadataForType(typeof(DummyModel)),
            ModelState = new ModelStateDictionary(),
            ValueProvider = valueProvider
        };

        // Act
        await binder.BindModelAsync(context);

        // Assert
        Assert.That(((DummyModel)context.Result.Model).Name, Is.EqualTo("test"));
    }
}
