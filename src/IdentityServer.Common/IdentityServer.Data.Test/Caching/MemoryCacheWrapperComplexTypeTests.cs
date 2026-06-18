using Microsoft.Extensions.Caching.Memory;
using IdentityServer.Core.Caching;

namespace IdentityServer.Data.Test.Caching;

[TestFixture]
public class MemoryCacheWrapperComplexTypeTests
{
    public class TestModel
    {
        public int Id { get; set; }
        public string Name { get; set; }
    }

    private MemoryCache _memoryCache;
    private MemoryCacheWrapper<TestModel> _service;

    [SetUp]
    public void SetUp()
    {
        var options = new MemoryCacheOptions();
        _memoryCache = new MemoryCache(options);
        _service = new MemoryCacheWrapper<TestModel>(_memoryCache);
    }

    [TearDown]
    public void TearDown()
    {
        _memoryCache.Dispose();
    }

    [Test]
    public void NormalizeKey_UsesComplexTypeName()
    {
        // Arrange
        var key = "TestKey";

        // Act
        var result = _service.NormalizeKey(key);

        // Assert
        Assert.That(result, Does.StartWith("testmodel:"));
    }

    [Test]
    public async Task GetAsync_ReturnsComplexObject_WhenKeyExists()
    {
        // Arrange
        var key = "ComplexKey";
        var expected = new TestModel { Id = 1, Name = "Test" };
        var normalizedKey = _service.NormalizeKey(key);
        _memoryCache.Set(normalizedKey, expected, TimeSpan.FromMinutes(1));

        // Act
        var result = await _service.GetAsync(key);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Id, Is.EqualTo(expected.Id));
            Assert.That(result.Name, Is.EqualTo(expected.Name));
        }
    }

    [Test]
    public async Task SetAsync_StoresComplexObject()
    {
        // Arrange
        var key = "ComplexKey";
        var value = new TestModel { Id = 42, Name = "Complex Test" };
        var expiration = TimeSpan.FromMinutes(5);
        var normalizedKey = _service.NormalizeKey(key);

        // Act
        await _service.SetAsync(key, value, expiration);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(_memoryCache.TryGetValue(normalizedKey, out TestModel result), Is.True);
            Assert.That(result.Id, Is.EqualTo(value.Id));
            Assert.That(result.Name, Is.EqualTo(value.Name));
        }
    }

    [Test]
    public async Task GetOrAddAsync_WorksWithComplexTypes()
    {
        // Arrange
        var key = "NewComplexKey";
        var newValue = new TestModel { Id = 99, Name = "Factory Created" };
        Task<TestModel> factory() => Task.FromResult(newValue);

        // Act
        var result = await _service.GetOrAddAsync(key, TimeSpan.FromMinutes(5), factory);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Id, Is.EqualTo(newValue.Id));
            Assert.That(result.Name, Is.EqualTo(newValue.Name));
        }
    }
}
