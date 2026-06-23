// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Caching.Memory;
using IdentityServer.Core.Caching;

namespace IdentityServer.Data.Test.Caching;

[TestFixture]
public class MemoryCacheWrapperTests
{
    private MemoryCache _memoryCache;
    private MemoryCacheWrapper<string> _service;

    [SetUp]
    public void SetUp()
    {
        var options = new MemoryCacheOptions();
        _memoryCache = new MemoryCache(options);
        _service = new MemoryCacheWrapper<string>(_memoryCache);
    }

    [TearDown]
    public void TearDown()
    {
        _memoryCache.Dispose();
    }

    [Test]
    public async Task GetAsync_ReturnsValue_WhenKeyExists()
    {
        // Arrange
        var key = "key";
        var normalizedKey = _service.NormalizeKey(key);
        var expected = "value";
        _memoryCache.Set(normalizedKey, expected, TimeSpan.FromMinutes(1));

        // Act
        var result = await _service.GetAsync(key);

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }

    [Test]
    public async Task GetAsync_ReturnsDefault_WhenKeyDoesNotExist()
    {
        // Arrange
        var key = "MissingKey";

        // Act
        var result = await _service.GetAsync(key);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public async Task GetAsync_NormalizesKey()
    {
        // Arrange
        var key = "MixedCaseKey";
        var normalizedKey = _service.NormalizeKey(key);
        var expected = "value";
        _memoryCache.Set(normalizedKey, expected, TimeSpan.FromMinutes(1));

        // Act
        var result = await _service.GetAsync(key);

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }

    [Test]
    public async Task SetAsync_SetsValueWithExpiration()
    {
        // Arrange
        var key = "key";
        var value = "42";
        var expiration = TimeSpan.FromMinutes(5);
        var normalizedKey = _service.NormalizeKey(key);

        // Act
        await _service.SetAsync(key, value, expiration);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(_memoryCache.TryGetValue(normalizedKey, out object result), Is.True);
            Assert.That(result, Is.EqualTo(value));
        }
    }

    [Test]
    public async Task SetAsync_NormalizesKey()
    {
        // Arrange
        var key = "MixedCaseKey";
        var value = "test value";
        var expiration = TimeSpan.FromMinutes(5);
        var normalizedKey = _service.NormalizeKey(key);

        // Act
        await _service.SetAsync(key, value, expiration);

        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(_memoryCache.TryGetValue(normalizedKey, out string result), Is.True);
            Assert.That(result, Is.EqualTo(value));
        }
    }

    [Test]
    public async Task SetAsync_ItemExpiresAfterDuration()
    {
        // Arrange
        var key = "ExpiringKey";
        var value = "expiring value";
        var expiration = TimeSpan.FromMilliseconds(100);
        var normalizedKey = _service.NormalizeKey(key);

        // Act
        await _service.SetAsync(key, value, expiration);

        // Assert - value exists immediately
        Assert.That(_memoryCache.TryGetValue(normalizedKey, out string _), Is.True);

        // Wait for expiration
        await Task.Delay(expiration + TimeSpan.FromMilliseconds(50));

        // Assert - value has expired
        Assert.That(_memoryCache.TryGetValue(normalizedKey, out string _), Is.False);
    }

    [Test]
    public async Task RemoveAsync_RemovesKey()
    {
        // Arrange
        var key = "key";
        var normalizedKey = _service.NormalizeKey(key);
        _memoryCache.Set(normalizedKey, 123, TimeSpan.FromMinutes(1));

        // Act
        await _service.RemoveAsync(key);

        // Assert
        Assert.That(_memoryCache.TryGetValue(normalizedKey, out _), Is.False);
    }

    [Test]
    public void RemoveAsync_DoesNotThrow_WhenKeyDoesNotExist()
    {
        // Arrange
        var key = "NonExistentKey";

        // Act & Assert
        Assert.DoesNotThrowAsync(async () => await _service.RemoveAsync(key));
    }

    [Test]
    public async Task RemoveAsync_NormalizesKey()
    {
        // Arrange
        var key = "MixedCaseKey";
        var normalizedKey = _service.NormalizeKey(key);
        _memoryCache.Set(normalizedKey, "value", TimeSpan.FromMinutes(1));

        // Act
        await _service.RemoveAsync(key);

        // Assert
        Assert.That(_memoryCache.TryGetValue(normalizedKey, out _), Is.False);
    }

    [Test]
    public void NormalizeKey_IncludesTypePrefixAndLowercases()
    {
        // Arrange
        var key = "MiXeDCaSe";
        var expected = "string:mixedcase";

        // Act
        var result = _service.NormalizeKey(key);

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }

    [Test]
    public void NormalizeKey_HandlesEmptyString()
    {
        // Arrange
        var key = "";
        var expected = "string:";

        // Act
        var result = _service.NormalizeKey(key);

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }

    [Test]
    public void NormalizeKey_HandlesSpecialCharacters()
    {
        // Arrange
        var key = "Key:With-Special_Characters.123";
        var expected = "string:key:with-special_characters.123";

        // Act
        var result = _service.NormalizeKey(key);

        // Assert
        Assert.That(result, Is.EqualTo(expected));
    }

    [Test]
    public async Task GetManyAsync_ReturnsMultipleValues_WhenKeysExist()
    {
        // Arrange
        var keys = new[] { "Key1", "Key2", "Key3" };
        var value1 = "value1";
        var value2 = "value2";
        var value3 = "value3";

        _memoryCache.Set(_service.NormalizeKey(keys[0]), value1, TimeSpan.FromMinutes(1));
        _memoryCache.Set(_service.NormalizeKey(keys[1]), value2, TimeSpan.FromMinutes(1));
        _memoryCache.Set(_service.NormalizeKey(keys[2]), value3, TimeSpan.FromMinutes(1));

        // Act
        var result = await _service.GetManyAsync(keys);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(3));
            Assert.That(result["Key1"], Is.EqualTo(value1));
            Assert.That(result["Key2"], Is.EqualTo(value2));
            Assert.That(result["Key3"], Is.EqualTo(value3));
        }
    }

    [Test]
    public async Task GetManyAsync_WhenDuplicateKeys_ReturnsExpected()
    {
        // Arrange
        var keys = new[] { "Key1", "Key1", "Key2" };
        var value1 = "value1";
        var value2 = "value2";

        _memoryCache.Set(_service.NormalizeKey(keys[0]), value1, TimeSpan.FromMinutes(1));
        _memoryCache.Set(_service.NormalizeKey(keys[2]), value2, TimeSpan.FromMinutes(1));

        // Act
        var result = await _service.GetManyAsync(keys);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result["Key1"], Is.EqualTo(value1));
            Assert.That(result["Key2"], Is.EqualTo(value2));
        }
    }

    [Test]
    public async Task GetManyAsync_ReturnsNullForMissingKeys()
    {
        // Arrange
        var keys = new[] { "ExistingKey", "MissingKey" };
        var existingValue = "value";
        _memoryCache.Set(_service.NormalizeKey(keys[0]), existingValue, TimeSpan.FromMinutes(1));

        // Act
        var result = await _service.GetManyAsync(keys);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result["ExistingKey"], Is.EqualTo(existingValue));
            Assert.That(result["MissingKey"], Is.Null);
        }
    }

    [Test]
    public async Task GetManyAsync_ReturnsEmptyDictionary_WhenKeysIsEmpty()
    {
        // Arrange
        var keys = Array.Empty<string>();

        // Act
        var result = await _service.GetManyAsync(keys);

        // Assert
        Assert.That(result, Is.Empty);
    }

    [Test]
    public async Task GetManyAsync_NormalizesKeys()
    {
        // Arrange
        var keys = new[] { "MixedKey1", "MixedKey2" };
        var value1 = "value1";
        var value2 = "value2";

        _memoryCache.Set(_service.NormalizeKey(keys[0]), value1, TimeSpan.FromMinutes(1));
        _memoryCache.Set(_service.NormalizeKey(keys[1]), value2, TimeSpan.FromMinutes(1));

        // Act
        var result = await _service.GetManyAsync(keys);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result["MixedKey1"], Is.EqualTo(value1));
            Assert.That(result["MixedKey2"], Is.EqualTo(value2));
        }
    }

    [Test]
    public async Task GetOrAddAsync_ReturnsExistingValue_WhenKeyExists()
    {
        // Arrange
        var key = "ExistingKey";
        var existingValue = "existing";
        var normalizedKey = _service.NormalizeKey(key);
        _memoryCache.Set(normalizedKey, existingValue, TimeSpan.FromMinutes(1));
        var factoryCalled = false;
        Task<string> factory()
        {
            factoryCalled = true;
            return Task.FromResult("new");
        }

        // Act
        var result = await _service.GetOrAddAsync(key, TimeSpan.FromMinutes(5), factory);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(existingValue));
            Assert.That(factoryCalled, Is.False);
        }
    }

    [Test]
    public async Task GetOrAddAsync_CallsFactoryAndSetsValue_WhenKeyDoesNotExist()
    {
        // Arrange
        var key = "key";
        var newValue = "new value";
        var normalizedKey = _service.NormalizeKey(key);
        var factoryCalled = false;
        Task<string> factory()
        {
            factoryCalled = true;
            return Task.FromResult(newValue);
        }

        // Act
        var result = await _service.GetOrAddAsync(key, TimeSpan.FromMinutes(5), factory);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(newValue));
            Assert.That(factoryCalled, Is.True);
            Assert.That(_memoryCache.TryGetValue(normalizedKey, out string cachedValue), Is.True);
            Assert.That(cachedValue, Is.EqualTo(newValue));
        }
    }

    [Test]
    public async Task GetOrAddAsync_NormalizesKey()
    {
        // Arrange
        var key = "MixedCaseKey";
        var newValue = "new value";
        var normalizedKey = _service.NormalizeKey(key);
        Task<string> factory() => Task.FromResult(newValue);

        // Act
        var result = await _service.GetOrAddAsync(key, TimeSpan.FromMinutes(5), factory);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(newValue));
            Assert.That(_memoryCache.TryGetValue(normalizedKey, out string cachedValue), Is.True);
            Assert.That(cachedValue, Is.EqualTo(newValue));
        }
    }

    [Test]
    public async Task GetOrAddAsync_ItemExpiresAfterDuration()
    {
        // Arrange
        var key = "ExpiringKey";
        var newValue = "expiring value";
        var normalizedKey = _service.NormalizeKey(key);
        var expiration = TimeSpan.FromMilliseconds(100);
        Task<string> factory() => Task.FromResult(newValue);

        // Act
        await _service.GetOrAddAsync(key, expiration, factory);

        // Assert - value exists immediately
        Assert.That(_memoryCache.TryGetValue(normalizedKey, out string _), Is.True);

        // Wait for expiration
        await Task.Delay(expiration + TimeSpan.FromMilliseconds(50));

        // Assert - value has expired
        Assert.That(_memoryCache.TryGetValue(normalizedKey, out string _), Is.False);
    }

    [Test]
    public async Task SetManyAsync_SetsMultipleValues()
    {
        // Arrange
        var items = new Dictionary<string, string>
        {
            { "Key1", "value1" },
            { "Key2", "value2" },
            { "Key3", "value3" }
        };
        var expiration = TimeSpan.FromMinutes(5);

        // Act
        await _service.SetManyAsync(items, expiration);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(_memoryCache.TryGetValue(_service.NormalizeKey("Key1"), out string value1), Is.True);
            Assert.That(value1, Is.EqualTo("value1"));
            Assert.That(_memoryCache.TryGetValue(_service.NormalizeKey("Key2"), out string value2), Is.True);
            Assert.That(value2, Is.EqualTo("value2"));
            Assert.That(_memoryCache.TryGetValue(_service.NormalizeKey("Key3"), out string value3), Is.True);
            Assert.That(value3, Is.EqualTo("value3"));
        }
    }

    [Test]
    public void SetManyAsync_HandlesEmptyDictionary()
    {
        // Arrange
        var items = new Dictionary<string, string>();
        var expiration = TimeSpan.FromMinutes(5);

        // Act & Assert
        Assert.DoesNotThrowAsync(async () => await _service.SetManyAsync(items, expiration));
    }

    [Test]
    public async Task SetManyAsync_NormalizesKeys()
    {
        // Arrange
        var items = new Dictionary<string, string>
        {
            { "MixedKey1", "value1" },
            { "MixedKey2", "value2" }
        };
        var expiration = TimeSpan.FromMinutes(5);
        var normalizedKey1 = _service.NormalizeKey(items.First().Key);
        var normalizedKey2 = _service.NormalizeKey(items.Last().Key);

        // Act
        await _service.SetManyAsync(items, expiration);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(_memoryCache.TryGetValue(normalizedKey1, out string value1), Is.True);
            Assert.That(value1, Is.EqualTo("value1"));
            Assert.That(_memoryCache.TryGetValue(normalizedKey2, out string value2), Is.True);
            Assert.That(value2, Is.EqualTo("value2"));
        }
    }

    [Test]
    public async Task SetManyAsync_ItemsExpireAfterDuration()
    {
        // Arrange
        var items = new Dictionary<string, string>
        {
            { "Key1", "value1" },
            { "Key2", "value2" },
            { "Key3", "value3" }
        };
        var expiration = TimeSpan.FromMilliseconds(100);
        var normalizedKey1 = _service.NormalizeKey("Key1");
        var normalizedKey2 = _service.NormalizeKey("Key2");
        var normalizedKey3 = _service.NormalizeKey("Key3");

        // Act
        await _service.SetManyAsync(items, expiration);

        // Assert - values exist immediately
        using (Assert.EnterMultipleScope())
        {
            Assert.That(_memoryCache.TryGetValue(normalizedKey1, out string _), Is.True);
            Assert.That(_memoryCache.TryGetValue(normalizedKey2, out string _), Is.True);
            Assert.That(_memoryCache.TryGetValue(normalizedKey3, out string _), Is.True);
        }

        // Wait for expiration
        await Task.Delay(expiration + TimeSpan.FromMilliseconds(50));

        // Assert - all values have expired
        using (Assert.EnterMultipleScope())
        {
            Assert.That(_memoryCache.TryGetValue(normalizedKey1, out string _), Is.False);
            Assert.That(_memoryCache.TryGetValue(normalizedKey2, out string _), Is.False);
            Assert.That(_memoryCache.TryGetValue(normalizedKey3, out string _), Is.False);
        }
    }
}
