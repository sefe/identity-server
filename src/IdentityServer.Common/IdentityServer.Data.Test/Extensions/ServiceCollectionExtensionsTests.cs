using Microsoft.Extensions.DependencyInjection;
using IdentityServer.Core.Extensions;

namespace IdentityServer.Data.Test.Extensions;

[TestFixture]
public class ServiceCollectionExtensionsTests
{
    private ServiceCollection _services;

    [SetUp]
    public void SetUp()
    {
        _services = new ServiceCollection();
    }

    [Test]
    public void Decorate_WithValidService_DecoratesLastRegisteredService()
    {
        // Arrange
        _services.AddSingleton<ITestService, TestService>();

        // Act
        _services.Decorate<ITestService, TestServiceDecorator>();
        var serviceProvider = _services.BuildServiceProvider();
        var result = serviceProvider.GetRequiredService<ITestService>();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.InstanceOf<TestServiceDecorator>());
            Assert.That(result.GetValue(), Is.EqualTo("Decorated: Test"));
        }
    }

    [Test]
    public void Decorate_WithMultipleRegistrations_DecoratesOnlyLastRegistration()
    {
        // Arrange
        _services.AddSingleton<ITestService, TestService>();
        _services.AddSingleton<ITestService, AlternativeTestService>();

        // Act
        _services.Decorate<ITestService, TestServiceDecorator>();
        var serviceProvider = _services.BuildServiceProvider();

        // Assert - verify the resolved service is the decorated last registration
        var result = serviceProvider.GetRequiredService<ITestService>();
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.InstanceOf<TestServiceDecorator>());
            Assert.That(result.GetValue(), Is.EqualTo("Decorated: Alternative"));
        }

        // Assert - verify the service collection state
        var descriptors = _services.Where(sd => sd.ServiceType == typeof(ITestService)).ToList();
        using (Assert.EnterMultipleScope())
        {
            // Should have 3 descriptors: original TestService (unchanged), keyed AlternativeTestService, and decorated service
            Assert.That(descriptors, Has.Count.EqualTo(3));

            // First registration should remain unchanged (not keyed, not decorated)
            var firstDescriptor = descriptors[0];
            Assert.That(firstDescriptor.ServiceKey, Is.Null);
            Assert.That(firstDescriptor.IsDecorated(), Is.False);
            Assert.That(firstDescriptor.ImplementationType, Is.EqualTo(typeof(TestService)));

            // Second registration should be keyed and marked as decorated (it was converted to keyed service)
            var secondDescriptor = descriptors[1];
            Assert.That(secondDescriptor.ServiceKey, Is.Not.Null);
            Assert.That(secondDescriptor.IsDecorated(), Is.True);
            Assert.That(secondDescriptor.KeyedImplementationType, Is.EqualTo(typeof(AlternativeTestService)));

            // Third descriptor should be the decorator with implementation factory
            var decoratorDescriptor = descriptors[2];
            Assert.That(decoratorDescriptor.ServiceKey, Is.Null);
            Assert.That(decoratorDescriptor.ImplementationFactory, Is.Not.Null);
            Assert.That(decoratorDescriptor.IsDecorated(), Is.False);
        }
    }

    [Test]
    public void Decorate_WithMultipleDecorators_AppliesAllDecoratorsInOrder()
    {
        // Arrange
        _services.AddSingleton<ITestService, TestService>();

        // Act
        _services.Decorate<ITestService, TestServiceDecorator>();
        _services.Decorate<ITestService, AnotherTestServiceDecorator>();
        var serviceProvider = _services.BuildServiceProvider();
        var result = serviceProvider.GetRequiredService<ITestService>();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.InstanceOf<AnotherTestServiceDecorator>());
            Assert.That(result.GetValue(), Is.EqualTo("Another: Decorated: Test"));
        }
    }

    [Test]
    public void Decorate_WithScopedService_PreservesServiceLifetime()
    {
        // Arrange
        _services.AddScoped<ITestService, TestService>();

        // Act
        _services.Decorate<ITestService, TestServiceDecorator>();

        // Assert
        var descriptor = _services.FirstOrDefault(sd => sd.ServiceType == typeof(ITestService) && !sd.IsDecorated());
        Assert.That(descriptor?.Lifetime, Is.EqualTo(ServiceLifetime.Scoped));
    }

    [Test]
    public void Decorate_WithTransientService_PreservesServiceLifetime()
    {
        // Arrange
        _services.AddTransient<ITestService, TestService>();

        // Act
        _services.Decorate<ITestService, TestServiceDecorator>();

        // Assert
        var descriptor = _services.FirstOrDefault(sd => sd.ServiceType == typeof(ITestService) && !sd.IsDecorated());
        Assert.That(descriptor?.Lifetime, Is.EqualTo(ServiceLifetime.Transient));
    }

    [Test]
    public void Decorate_WithFactoryRegistration_DecoratesCorrectly()
    {
        // Arrange
        _services.AddSingleton<ITestService>(sp => new TestService());

        // Act
        _services.Decorate<ITestService, TestServiceDecorator>();
        var serviceProvider = _services.BuildServiceProvider();
        var result = serviceProvider.GetRequiredService<ITestService>();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.InstanceOf<TestServiceDecorator>());
            Assert.That(result.GetValue(), Is.EqualTo("Decorated: Test"));
        }
    }

    [Test]
    public void Decorate_WithInstanceRegistration_DecoratesCorrectly()
    {
        // Arrange
        var instance = new TestService();
        _services.AddSingleton<ITestService>(instance);

        // Act
        _services.Decorate<ITestService, TestServiceDecorator>();
        var serviceProvider = _services.BuildServiceProvider();
        var result = serviceProvider.GetRequiredService<ITestService>();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.InstanceOf<TestServiceDecorator>());
            Assert.That(result.GetValue(), Is.EqualTo("Decorated: Test"));
        }
    }

    [Test]
    public void Decorate_WithNullServices_ThrowsArgumentNullException()
    {
        // Arrange
        IServiceCollection nullServices = null;

        // Act & Assert
        Assert.Throws<ArgumentNullException>(() =>
                nullServices.Decorate<ITestService, TestServiceDecorator>());
    }

    [Test]
    public void Decorate_WithNoMatchingService_DoesNotModifyServices()
    {
        // Arrange
        var initialCount = _services.Count;

        // Act
        _services.Decorate<ITestService, TestServiceDecorator>();

        // Assert
        Assert.That(_services, Has.Count.EqualTo(initialCount));
    }

    [Test]
    public void Decorate_WithAlreadyDecoratedService_SkipsDecoratedService()
    {
        // Arrange
        _services.AddSingleton<ITestService, TestService>();
        _services.Decorate<ITestService, TestServiceDecorator>();
        _services.AddSingleton<ITestService, AlternativeTestService>();

        // Act
        _services.Decorate<ITestService, AnotherTestServiceDecorator>();
        var serviceProvider = _services.BuildServiceProvider();
        var result = serviceProvider.GetRequiredService<ITestService>();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.InstanceOf<AnotherTestServiceDecorator>());
            Assert.That(result.GetValue(), Is.EqualTo("Another: Alternative"));
        }
    }

    [Test]
    public void Decorate_WithKeyedService_DecoratesCorrectly()
    {
        // Arrange
        _services.AddKeyedSingleton<ITestService, TestService>("myKey");

        // Act
        _services.Decorate<ITestService, TestServiceDecorator>();
        var serviceProvider = _services.BuildServiceProvider();

        // Assert - the decorated service is registered with the original key
        var result = serviceProvider.GetRequiredKeyedService<ITestService>("myKey");
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.InstanceOf<TestServiceDecorator>());
            Assert.That(result.GetValue(), Is.EqualTo("Decorated: Test"));
        }
    }

    [Test]
    public void Decorate_WithDecoratorRequiringDependencies_ResolvesDependencies()
    {
        // Arrange
        _services.AddSingleton<IDependency, Dependency>();
        _services.AddSingleton<ITestService, TestService>();

        // Act
        _services.Decorate<ITestService, TestServiceDecoratorWithDependency>();
        var serviceProvider = _services.BuildServiceProvider();
        var result = serviceProvider.GetRequiredService<ITestService>();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.InstanceOf<TestServiceDecoratorWithDependency>());
            Assert.That(result.GetValue(), Is.EqualTo("DecoratedWithDep: Test - Dependency"));
        }
    }

    [Test]
    public void IsDecorated_WithDecoratedService_ReturnsTrue()
    {
        // Arrange
        _services.AddSingleton<ITestService, TestService>();
        _services.Decorate<ITestService, TestServiceDecorator>();

        // Act
        var decoratedDescriptor = _services.First(sd => sd.ServiceType == typeof(ITestService) && sd.IsDecorated());

        // Assert
        Assert.That(decoratedDescriptor.IsDecorated(), Is.True);
    }

    [Test]
    public void IsDecorated_WithNonDecoratedService_ReturnsFalse()
    {
        // Arrange
        _services.AddSingleton<ITestService, TestService>();

        // Act
        var descriptor = _services.First(sd => sd.ServiceType == typeof(ITestService));

        // Assert
        Assert.That(descriptor.IsDecorated(), Is.False);
    }

    [Test]
    public void IsDecorated_WithServiceWithoutKey_ReturnsFalse()
    {
        // Arrange
        var descriptor = new ServiceDescriptor(typeof(ITestService), typeof(TestService), ServiceLifetime.Singleton);

        // Act
        var result = descriptor.IsDecorated();

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void IsDecorated_WithServiceWithNonStringKey_ReturnsFalse()
    {
        // Arrange
        var descriptor = new ServiceDescriptor(typeof(ITestService), 123, (sp, key) => new TestService(), ServiceLifetime.Singleton);

        // Act
        var result = descriptor.IsDecorated();

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void IsDecorated_WithServiceWithStringKeyNotEndingWithSuffix_ReturnsFalse()
    {
        // Arrange
        var descriptor = new ServiceDescriptor(typeof(ITestService), "myKey", (sp, key) => new TestService(), ServiceLifetime.Singleton);

        // Act
        var result = descriptor.IsDecorated();

        // Assert
        Assert.That(result, Is.False);
    }

    // Test interfaces and implementations
    public interface ITestService
    {
        string GetValue();
    }

    public class TestService : ITestService
    {
        public string GetValue() => "Test";
    }

    public class AlternativeTestService : ITestService
    {
        public string GetValue() => "Alternative";
    }

    public class TestServiceDecorator : ITestService
    {
        private readonly ITestService _inner;

        public TestServiceDecorator(ITestService inner)
        {
            _inner = inner;
        }

        public string GetValue() => $"Decorated: {_inner.GetValue()}";
    }

    public class AnotherTestServiceDecorator : ITestService
    {
        private readonly ITestService _inner;

        public AnotherTestServiceDecorator(ITestService inner)
        {
            _inner = inner;
        }

        public string GetValue() => $"Another: {_inner.GetValue()}";
    }

    public interface IDependency
    {
        string GetDependencyValue();
    }

    public class Dependency : IDependency
    {
        public string GetDependencyValue() => "Dependency";
    }

    public class TestServiceDecoratorWithDependency : ITestService
    {
        private readonly ITestService _inner;
        private readonly IDependency _dependency;

        public TestServiceDecoratorWithDependency(ITestService inner, IDependency dependency)
        {
            _inner = inner;
            _dependency = dependency;
        }

        public string GetValue() => $"DecoratedWithDep: {_inner.GetValue()} - {_dependency.GetDependencyValue()}";
    }
}
