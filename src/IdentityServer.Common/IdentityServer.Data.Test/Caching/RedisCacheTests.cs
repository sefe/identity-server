// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using StackExchange.Redis;
using IdentityServer.Abstraction.Configs;
using IdentityServer.Core.Caching;

namespace IdentityServer.Data.Test.Caching;

[TestFixture]
public class RedisCacheTests
{
    private const string _testKey = "test-key";
    private const string _normalizedKey = "test-env:testdata:test-key";
    private const string _environmentName = "test-env";

    private IConnectionMultiplexer _connectionMultiplexer;
    private IDatabase _database;
    private ISystemConfig _systemConfig;
    private ILogger<RedisCache<TestData>> _logger;
    private RedisCache<TestData> _cache;

    [SetUp]
    public void SetUp()
    {
        _connectionMultiplexer = Substitute.For<IConnectionMultiplexer>();
        _database = Substitute.For<IDatabase>();
        _systemConfig = Substitute.For<ISystemConfig>();
        _logger = NullLogger<RedisCache<TestData>>.Instance;

        _connectionMultiplexer.GetDatabase(Arg.Any<int>(), Arg.Any<object>()).Returns(_database);
        _systemConfig.Environment.Returns(_environmentName);

        _cache = new RedisCache<TestData>(_connectionMultiplexer, _systemConfig, _logger);
    }

    [TearDown]
    public void TearDown()
    {
        _connectionMultiplexer?.Dispose();
    }

    #region Constructor Tests

    [Test]
    public void Constructor_WithNullConnectionMultiplexer_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        Assert.Throws<ArgumentNullException>(() => new RedisCache<TestData>(null!, _systemConfig, _logger));
    }

    [Test]
    public void Constructor_WithNullLogger_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        Assert.Throws<ArgumentNullException>(() => new RedisCache<TestData>(_connectionMultiplexer, _systemConfig, null!));
    }

    #endregion

    #region GetAsync Tests

    [Test]
    public void GetAsync_WithNullKey_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentNullException>(async () => await _cache.GetAsync(null!));
        Assert.That(exception!.ParamName, Is.EqualTo("key"));
    }

    [Test]
    public void GetAsync_WithEmptyKey_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentException>(async () => await _cache.GetAsync(string.Empty));
        Assert.That(exception!.ParamName, Is.EqualTo("key"));
    }

    [Test]
    public async Task GetAsync_WithExistingKey_ReturnsDeserializedValue()
    {
        // Arrange
        var testData = new TestData { Id = 1, Name = "Test" };
        var json = System.Text.Json.JsonSerializer.Serialize(testData);
        _database.StringGetAsync(_normalizedKey, Arg.Any<CommandFlags>()).Returns(new RedisValue(json));

        // Act
        var result = await _cache.GetAsync(_testKey);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result!.Id, Is.EqualTo(testData.Id));
            Assert.That(result.Name, Is.EqualTo(testData.Name));
        }
    }

    [Test]
    public async Task GetAsync_WithNonExistentKey_ReturnsNull()
    {
        // Arrange
        _database.StringGetAsync(_normalizedKey, Arg.Any<CommandFlags>()).Returns(RedisValue.Null);

        // Act
        var result = await _cache.GetAsync(_testKey);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public async Task GetAsync_NormalizesKeysToLowerCase()
    {
        // Arrange
        const string UppercaseKey = "TEST-KEY";
        var normalizedUppercaseKey = _environmentName + ":testdata:" + UppercaseKey.ToLowerInvariant();
        _database.StringGetAsync(normalizedUppercaseKey, Arg.Any<CommandFlags>()).Returns(RedisValue.Null);

        // Act
        await _cache.GetAsync(UppercaseKey);

        // Assert
        await _database.Received(1).StringGetAsync(normalizedUppercaseKey, Arg.Any<CommandFlags>());
    }

    [Test]
    public async Task GetAsync_WhenDatabaseThrowsException_ReturnsNullWithoutPropagatingException()
    {
        // Arrange
        _database.StringGetAsync(Arg.Any<RedisKey>(), Arg.Any<CommandFlags>())
            .Returns<RedisValue>(_ => throw new RedisConnectionException(ConnectionFailureType.UnableToConnect, "Connection failed"));

        // Act
        var result = await _cache.GetAsync(_testKey);

        // Assert
        Assert.That(result, Is.Null);
    }

    #endregion

    #region GetManyAsync Tests

    [Test]
    public void GetManyAsync_WithNullKeys_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentNullException>(async () => await _cache.GetManyAsync(null!));
        Assert.That(exception!.ParamName, Is.EqualTo("keys"));
    }

    [Test]
    public async Task GetManyAsync_WithEmptyKeyList_ReturnsEmptyDictionary()
    {
        // Arrange
        var keys = new List<string>();

        // Act
        var result = await _cache.GetManyAsync(keys);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Is.Empty);
        }
    }

    [Test]
    public async Task GetManyAsync_WithSingleKey_ReturnsSingleItem()
    {
        // Arrange
        var key = "key1";
        var testData = new TestData { Id = 1, Name = "Test1" };
        var json = System.Text.Json.JsonSerializer.Serialize(testData);
        var normalizedKey = _environmentName + ":testdata:" + key;

        _database.StringGetAsync(Arg.Is<RedisKey[]>(keys => keys.Length == 1 && keys[0] == normalizedKey), Arg.Any<CommandFlags>())
            .Returns(new[] { new RedisValue(json) });

        // Act
        var result = await _cache.GetManyAsync(new[] { key });

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(1));
            Assert.That(result[key], Is.Not.Null);
            Assert.That(result[key]!.Id, Is.EqualTo(testData.Id));
            Assert.That(result[key]!.Name, Is.EqualTo(testData.Name));
        }
    }

    [Test]
    public async Task GetManyAsync_WithMultipleKeys_ReturnsAllItems()
    {
        // Arrange
        var keys = new[] { "key1", "key2", "key3" };
        var testData1 = new TestData { Id = 1, Name = "Test1" };
        var testData2 = new TestData { Id = 2, Name = "Test2" };
        var testData3 = new TestData { Id = 3, Name = "Test3" };

        var json1 = System.Text.Json.JsonSerializer.Serialize(testData1);
        var json2 = System.Text.Json.JsonSerializer.Serialize(testData2);
        var json3 = System.Text.Json.JsonSerializer.Serialize(testData3);

        _database.StringGetAsync(Arg.Any<RedisKey[]>(), Arg.Any<CommandFlags>())
            .Returns(new[] { new RedisValue(json1), new RedisValue(json2), new RedisValue(json3) });

        // Act
        var result = await _cache.GetManyAsync(keys);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(3));
            Assert.That(result["key1"]!.Id, Is.EqualTo(1));
            Assert.That(result["key2"]!.Id, Is.EqualTo(2));
            Assert.That(result["key3"]!.Id, Is.EqualTo(3));
        }
    }

    [Test]
    public async Task GetManyAsync_WithMixOfExistingAndNonExistingKeys_ReturnsMixedResults()
    {
        // Arrange
        var keys = new[] { "key1", "key2", "key3" };
        var testData1 = new TestData { Id = 1, Name = "Test1" };
        var json1 = System.Text.Json.JsonSerializer.Serialize(testData1);

        _database.StringGetAsync(Arg.Any<RedisKey[]>(), Arg.Any<CommandFlags>())
            .Returns(new[] { new RedisValue(json1), RedisValue.Null, RedisValue.Null });

        // Act
        var result = await _cache.GetManyAsync(keys);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(3));
            Assert.That(result["key1"], Is.Not.Null);
            Assert.That(result["key2"], Is.Null);
            Assert.That(result["key3"], Is.Null);
        }
    }

    [Test]
    public async Task GetManyAsync_NormalizesKeysToLowerCase()
    {
        // Arrange
        var keys = new[] { "KEY1", "Key2", "key3" };
        var normalizedKey1 = _environmentName + ":testdata:key1";
        var normalizedKey2 = _environmentName + ":testdata:key2";
        var normalizedKey3 = _environmentName + ":testdata:key3";

        _database.StringGetAsync(Arg.Any<RedisKey[]>(), Arg.Any<CommandFlags>())
            .Returns(new[] { RedisValue.Null, RedisValue.Null, RedisValue.Null });

        // Act
        await _cache.GetManyAsync(keys);

        // Assert
        await _database.Received(1).StringGetAsync(
            Arg.Is<RedisKey[]>(redisKeys =>
                redisKeys.Length == 3 &&
                redisKeys[0] == normalizedKey1 &&
                redisKeys[1] == normalizedKey2 &&
                redisKeys[2] == normalizedKey3),
            Arg.Any<CommandFlags>());
    }

    [Test]
    public async Task GetManyAsync_WithInvalidJson_ReturnsNullForInvalidItem()
    {
        // Arrange
        var keys = new[] { "key1", "key2" };
        var testData = new TestData { Id = 1, Name = "Test1" };
        var validJson = System.Text.Json.JsonSerializer.Serialize(testData);
        var invalidJson = "{invalid json}";

        _database.StringGetAsync(Arg.Any<RedisKey[]>(), Arg.Any<CommandFlags>())
            .Returns(new[] { new RedisValue(validJson), new RedisValue(invalidJson) });

        // Act
        var result = await _cache.GetManyAsync(keys);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result["key1"], Is.Not.Null);
            Assert.That(result["key2"], Is.Null);
        }
    }

    [Test]
    public async Task GetManyAsync_WhenDatabaseThrowsException_ReturnsEmptyDictionaryWithNullValues()
    {
        // Arrange
        var keys = new[] { "key1", "key2" };
        _database.StringGetAsync(Arg.Any<RedisKey[]>(), Arg.Any<CommandFlags>())
            .Returns<RedisValue[]>(_ => throw new RedisConnectionException(ConnectionFailureType.UnableToConnect, "Connection failed"));

        // Act
        var result = await _cache.GetManyAsync(keys);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(2));
            Assert.That(result["key1"], Is.Null);
            Assert.That(result["key2"], Is.Null);
        }
    }

    #endregion

    #region SetAsync Tests

    [Test]
    public void SetAsync_WithNullKey_ThrowsArgumentNullException()
    {
        // Arrange
        var testData = new TestData { Id = 1, Name = "Test" };

        // Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentNullException>(async () =>
            await _cache.SetAsync(null!, testData, TimeSpan.FromMinutes(5)));
        Assert.That(exception!.ParamName, Is.EqualTo("key"));
    }

    [Test]
    public void SetAsync_WithEmptyKey_ThrowsArgumentNullException()
    {
        // Arrange
        var testData = new TestData { Id = 1, Name = "Test" };

        // Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentException>(async () =>
            await _cache.SetAsync(string.Empty, testData, TimeSpan.FromMinutes(5)));
        Assert.That(exception!.ParamName, Is.EqualTo("key"));
    }

    [Test]
    public void SetAsync_WithNullItem_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentNullException>(async () =>
            await _cache.SetAsync(_testKey, null!, TimeSpan.FromMinutes(5)));
        Assert.That(exception!.ParamName, Is.EqualTo("item"));
    }

    [Test]
    public async Task SetAsync_WithValidData_SerializesAndStoresValue()
    {
        // Arrange
        const int ExpectedId = 42;
        const string ExpectedName = "Integration Test";
        var testData = new TestData { Id = ExpectedId, Name = ExpectedName };
        var expiration = TimeSpan.FromMinutes(10);
        _database.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns(true);

        // Act
        await _cache.SetAsync(_testKey, testData, expiration);

        // Assert
        await _database.Received(1).StringSetAsync(
            Arg.Is<RedisKey>(k => k == _normalizedKey),
            Arg.Is<RedisValue>(v => v.ToString().Contains($"\"Id\":{ExpectedId}") && v.ToString().Contains($"\"Name\":\"{ExpectedName}\"")),
            Arg.Is<TimeSpan?>(ts => ts == expiration),
            Arg.Any<bool>(),
            Arg.Any<When>(),
            Arg.Any<CommandFlags>());
    }

    [Test]
    public async Task SetAsync_NormalizesKeysToLowerCase()
    {
        // Arrange
        const string UppercaseKey = "TEST-KEY";
        var normalizedUppercaseKey = _environmentName + ":testdata:" + UppercaseKey.ToLowerInvariant();
        var testData = new TestData { Id = 1, Name = "Test" };
        _database.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns(true);

        // Act
        await _cache.SetAsync(UppercaseKey, testData, TimeSpan.FromMinutes(5));

        // Assert
        await _database.Received(1).StringSetAsync(
            Arg.Is<RedisKey>(k => k == normalizedUppercaseKey),
            Arg.Any<RedisValue>(),
            Arg.Any<TimeSpan?>(),
            Arg.Any<bool>(),
            Arg.Any<When>(),
            Arg.Any<CommandFlags>());
    }

    [Test]
    public void SetAsync_WhenDatabaseThrowsException_DoesNotPropagateException()
    {
        // Arrange
        var testData = new TestData { Id = 1, Name = "Test" };
        _database.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns<bool>(_ => throw new RedisConnectionException(ConnectionFailureType.UnableToConnect, "Connection failed"));

        // Act & Assert
        Assert.DoesNotThrowAsync(async () => await _cache.SetAsync(_testKey, testData, TimeSpan.FromMinutes(5)));
    }

    #endregion

    #region SetManyAsync Tests

    [Test]
    public void SetManyAsync_WithNullItems_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentNullException>(async () =>
            await _cache.SetManyAsync(null!, TimeSpan.FromMinutes(5)));
        Assert.That(exception!.ParamName, Is.EqualTo("items"));
    }

    [Test]
    public async Task SetManyAsync_WithEmptyDictionary_DoesNothing()
    {
        // Arrange
        var items = new Dictionary<string, TestData>();

        // Act
        await _cache.SetManyAsync(items, TimeSpan.FromMinutes(5));

        // Assert
        _database.DidNotReceive().CreateBatch(Arg.Any<object>());
    }

    [Test]
    public async Task SetManyAsync_WithSingleItem_StoresItem()
    {
        // Arrange
        var items = new Dictionary<string, TestData>
        {
            { "key1", new TestData { Id = 1, Name = "Test1" } }
        };
        var expiration = TimeSpan.FromMinutes(10);
        var batch = Substitute.For<IBatch>();
        _database.CreateBatch(Arg.Any<object>()).Returns(batch);
        batch.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns(Task.FromResult(true));

        // Act
        await _cache.SetManyAsync(items, expiration);

        // Assert
        batch.Received(1).Execute();
        await batch.Received(1).StringSetAsync(
            Arg.Is<RedisKey>(k => k.ToString().Contains("key1")),
            Arg.Any<RedisValue>(),
            Arg.Is<TimeSpan?>(ts => ts == expiration),
            Arg.Any<bool>(),
            Arg.Any<When>(),
            Arg.Any<CommandFlags>());
    }

    [Test]
    public async Task SetManyAsync_WithMultipleItems_StoresAllItems()
    {
        // Arrange
        var items = new Dictionary<string, TestData>
        {
            { "key1", new TestData { Id = 1, Name = "Test1" } },
            { "key2", new TestData { Id = 2, Name = "Test2" } },
            { "key3", new TestData { Id = 3, Name = "Test3" } }
        };
        var expiration = TimeSpan.FromMinutes(15);
        var batch = Substitute.For<IBatch>();
        _database.CreateBatch(Arg.Any<object>()).Returns(batch);
        batch.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns(Task.FromResult(true));

        // Act
        await _cache.SetManyAsync(items, expiration);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            batch.Received(1).Execute();
            await batch.Received(3).StringSetAsync(
                Arg.Any<RedisKey>(),
                Arg.Any<RedisValue>(),
                Arg.Is<TimeSpan?>(ts => ts == expiration),
                Arg.Any<bool>(),
                Arg.Any<When>(),
                Arg.Any<CommandFlags>());
        }
    }

    [Test]
    public async Task SetManyAsync_NormalizesKeysToLowerCase()
    {
        // Arrange
        var items = new Dictionary<string, TestData>
        {
            { "KEY1", new TestData { Id = 1, Name = "Test1" } },
            { "Key2", new TestData { Id = 2, Name = "Test2" } }
        };
        var expiration = TimeSpan.FromMinutes(5);
        var batch = Substitute.For<IBatch>();
        var normalizedKey1 = _environmentName + ":testdata:key1";
        var normalizedKey2 = _environmentName + ":testdata:key2";

        _database.CreateBatch(Arg.Any<object>()).Returns(batch);
        batch.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns(Task.FromResult(true));

        // Act
        await _cache.SetManyAsync(items, expiration);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            await batch.Received(1).StringSetAsync(
                Arg.Is<RedisKey>(k => k == normalizedKey1),
                Arg.Any<RedisValue>(),
                Arg.Any<TimeSpan?>(),
                Arg.Any<bool>(),
                Arg.Any<When>(),
                Arg.Any<CommandFlags>());
            await batch.Received(1).StringSetAsync(
                Arg.Is<RedisKey>(k => k == normalizedKey2),
                Arg.Any<RedisValue>(),
                Arg.Any<TimeSpan?>(),
                Arg.Any<bool>(),
                Arg.Any<When>(),
                Arg.Any<CommandFlags>());
        }
    }

    [Test]
    public async Task SetManyAsync_SerializesItemsCorrectly()
    {
        // Arrange
        var items = new Dictionary<string, TestData>
        {
            { "key1", new TestData { Id = 42, Name = "Test Item" } }
        };
        var expiration = TimeSpan.FromMinutes(5);
        var batch = Substitute.For<IBatch>();
        _database.CreateBatch(Arg.Any<object>()).Returns(batch);
        batch.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns(Task.FromResult(true));

        // Act
        await _cache.SetManyAsync(items, expiration);

        // Assert
        await batch.Received(1).StringSetAsync(
            Arg.Any<RedisKey>(),
            Arg.Is<RedisValue>(v => v.ToString().Contains("\"Id\":42") && v.ToString().Contains("\"Name\":\"Test Item\"")),
            Arg.Any<TimeSpan?>(),
            Arg.Any<bool>(),
            Arg.Any<When>(),
            Arg.Any<CommandFlags>());
    }

    [Test]
    public void SetManyAsync_WhenDatabaseThrowsException_DoesNotPropagateException()
    {
        // Arrange
        var items = new Dictionary<string, TestData>
        {
            { "key1", new TestData { Id = 1, Name = "Test1" } }
        };
        _database.CreateBatch(Arg.Any<object>())
                 .Returns(_ => throw new RedisConnectionException(ConnectionFailureType.UnableToConnect, "Connection failed"));

        // Act & Assert
        Assert.DoesNotThrowAsync(async () => await _cache.SetManyAsync(items, TimeSpan.FromMinutes(5)));
    }

    [Test]
    public void SetManyAsync_WhenBatchExecuteThrowsException_DoesNotPropagateException()
    {
        // Arrange
        var items = new Dictionary<string, TestData>
        {
            { "key1", new TestData { Id = 1, Name = "Test1" } }
        };
        var batch = Substitute.For<IBatch>();
        _database.CreateBatch(Arg.Any<object>()).Returns(batch);
        batch.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns(Task.FromResult(true));
        batch.When(b => b.Execute()).Do(_ => throw new RedisConnectionException(ConnectionFailureType.UnableToConnect, "Connection failed"));

        // Act & Assert
        Assert.DoesNotThrowAsync(async () => await _cache.SetManyAsync(items, TimeSpan.FromMinutes(5)));
    }

    #endregion

    #region RemoveAsync Tests

    [Test]
    public void RemoveAsync_WithNullKey_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentNullException>(async () => await _cache.RemoveAsync(null!));
        Assert.That(exception!.ParamName, Is.EqualTo("key"));
    }

    [Test]
    public void RemoveAsync_WithEmptyKey_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentException>(async () => await _cache.RemoveAsync(string.Empty));
        Assert.That(exception!.ParamName, Is.EqualTo("key"));
    }

    [Test]
    public async Task RemoveAsync_WithValidKey_CallsKeyDelete()
    {
        // Arrange
        _database.KeyDeleteAsync(Arg.Any<RedisKey>(), Arg.Any<CommandFlags>()).Returns(true);

        // Act
        await _cache.RemoveAsync(_testKey);

        // Assert
        await _database.Received(1).KeyDeleteAsync(
            Arg.Is<RedisKey>(k => k == _normalizedKey),
            Arg.Any<CommandFlags>());
    }

    [Test]
    public async Task RemoveAsync_NormalizesKeysToLowerCase()
    {
        // Arrange
        const string UppercaseKey = "TEST-KEY";
        var normalizedUppercaseKey = _environmentName + ":testdata:" + UppercaseKey.ToLowerInvariant();
        _database.KeyDeleteAsync(Arg.Any<RedisKey>(), Arg.Any<CommandFlags>()).Returns(true);

        // Act
        await _cache.RemoveAsync(UppercaseKey);

        // Assert
        await _database.Received(1).KeyDeleteAsync(
            Arg.Is<RedisKey>(k => k == normalizedUppercaseKey),
            Arg.Any<CommandFlags>());
    }

    [Test]
    public void RemoveAsync_WhenDatabaseThrowsException_DoesNotPropagateException()
    {
        // Arrange
        _database.KeyDeleteAsync(Arg.Any<RedisKey>(), Arg.Any<CommandFlags>())
            .Returns<bool>(_ => throw new RedisConnectionException(ConnectionFailureType.UnableToConnect, "Connection failed"));

        // Act & Assert
        Assert.DoesNotThrowAsync(async () => await _cache.RemoveAsync(_testKey));
    }

    #endregion

    #region GetOrAddAsync Tests

    [Test]
    public void GetOrAddAsync_WithNullKey_ThrowsArgumentNullException()
    {
        // Arrange
        static Task<TestData> get() => Task.FromResult(new TestData { Id = 1, Name = "Test" });

        // Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentNullException>(async () =>
            await _cache.GetOrAddAsync(null!, TimeSpan.FromMinutes(5), get));
        Assert.That(exception!.ParamName, Is.EqualTo("key"));
    }

    [Test]
    public void GetOrAddAsync_WithEmptyKey_ThrowsArgumentNullException()
    {
        // Arrange
        static Task<TestData> get() => Task.FromResult(new TestData { Id = 1, Name = "Test" });

        // Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentException>(async () =>
            await _cache.GetOrAddAsync(string.Empty, TimeSpan.FromMinutes(5), get));
        Assert.That(exception!.ParamName, Is.EqualTo("key"));
    }

    [Test]
    public void GetOrAddAsync_WithNullGetFunction_ThrowsArgumentNullException()
    {
        // Arrange, Act & Assert
        var exception = Assert.ThrowsAsync<ArgumentNullException>(async () =>
              await _cache.GetOrAddAsync(_testKey, TimeSpan.FromMinutes(5), null!));
        Assert.That(exception!.ParamName, Is.EqualTo("get"));
    }

    [Test]
    public async Task GetOrAddAsync_WhenCacheHit_ReturnsFromCacheWithoutCallingGet()
    {
        // Arrange
        const int CachedId = 1;
        const string CachedName = "Cached";
        const string GetFunctionShouldNotBeCalledMessage = "Get function should not be called on cache hit";

        var cachedData = new TestData { Id = CachedId, Name = CachedName };
        var json = System.Text.Json.JsonSerializer.Serialize(cachedData);
        _database.StringGetAsync(_normalizedKey, Arg.Any<CommandFlags>()).Returns(new RedisValue(json));

        var getFunctionCalled = false;
        Task<TestData> get()
        {
            getFunctionCalled = true;
            return Task.FromResult(new TestData { Id = 2, Name = "Fresh" });
        }

        // Act
        var result = await _cache.GetOrAddAsync(_testKey, TimeSpan.FromMinutes(5), get);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Id, Is.EqualTo(cachedData.Id));
            Assert.That(result.Name, Is.EqualTo(cachedData.Name));
            Assert.That(getFunctionCalled, Is.False, GetFunctionShouldNotBeCalledMessage);
        }
    }

    [Test]
    public async Task GetOrAddAsync_WhenCacheMiss_CallsGetAndStoresResult()
    {
        // Arrange
        const int FreshId = 3;
        const string FreshName = "Fresh Data";
        const string GetFunctionShouldBeCalledMessage = "Get function should be called on cache miss";

        var freshData = new TestData { Id = FreshId, Name = FreshName };
        var duration = TimeSpan.FromMinutes(15);

        _database.StringGetAsync(_normalizedKey, Arg.Any<CommandFlags>()).Returns(RedisValue.Null);
        _database.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns(true);

        var getFunctionCalled = false;
        Task<TestData> get()
        {
            getFunctionCalled = true;
            return Task.FromResult(freshData);
        }

        // Act
        var result = await _cache.GetOrAddAsync(_testKey, duration, get);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Id, Is.EqualTo(freshData.Id));
            Assert.That(result.Name, Is.EqualTo(freshData.Name));
            Assert.That(getFunctionCalled, Is.True, GetFunctionShouldBeCalledMessage);

            await _database.Received(1).StringSetAsync(
                Arg.Is<RedisKey>(k => k == _normalizedKey),
                Arg.Any<RedisValue>(),
                Arg.Is<TimeSpan?>(ts => ts == duration),
                Arg.Any<bool>(),
                Arg.Any<When>(),
                Arg.Any<CommandFlags>());
        }
    }

    [Test]
    public async Task GetOrAddAsync_WhenGetReturnsNull_DoesNotStore()
    {
        // Arrange
        _database.StringGetAsync(_normalizedKey, Arg.Any<CommandFlags>()).Returns(RedisValue.Null);

        static Task<TestData> get() => Task.FromResult<TestData>(null!);

        // Act
        var result = await _cache.GetOrAddAsync(_testKey, TimeSpan.FromMinutes(5), get);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Null);
            await _database.DidNotReceive().StringSetAsync(
                Arg.Any<RedisKey>(),
                Arg.Any<RedisValue>(),
                Arg.Any<TimeSpan?>(),
                Arg.Any<bool>(),
                Arg.Any<When>(),
                Arg.Any<CommandFlags>());
        }
    }

    [Test]
    public async Task GetOrAddAsync_WhenCachedValueIsInvalid_CallsGetAndStoresResult()
    {
        // Arrange
        const string InvalidJson = "{invalid}";
        const int ValidId = 4;
        const string ValidName = "Valid Data";

        var freshData = new TestData { Id = ValidId, Name = ValidName };
        var duration = TimeSpan.FromMinutes(20);

        _database.StringGetAsync(_normalizedKey, Arg.Any<CommandFlags>()).Returns(new RedisValue(InvalidJson));
        _database.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns(true);

        Task<TestData> get() => Task.FromResult(freshData);

        // Act
        var result = await _cache.GetOrAddAsync(_testKey, duration, get);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Id, Is.EqualTo(freshData.Id));

            await _database.Received(1).StringSetAsync(
                Arg.Is<RedisKey>(k => k == _normalizedKey),
                Arg.Any<RedisValue>(),
                Arg.Is<TimeSpan?>(ts => ts == duration),
                Arg.Any<bool>(),
                Arg.Any<When>(),
                Arg.Any<CommandFlags>());
        }
    }

    [Test]
    public async Task GetOrAddAsync_WhenDatabaseThrowsExceptionOnGet_ReturnsNullWithoutPropagatingException()
    {
        // Arrange
        _database.StringGetAsync(Arg.Any<RedisKey>(), Arg.Any<CommandFlags>())
            .Returns<RedisValue>(_ => throw new RedisConnectionException(ConnectionFailureType.UnableToConnect, "Connection failed"));

        static Task<TestData> get() => Task.FromResult(new TestData { Id = 1, Name = "Test" });

        // Act
        var result = await _cache.GetOrAddAsync(_testKey, TimeSpan.FromMinutes(5), get);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public async Task GetOrAddAsync_WhenDatabaseThrowsExceptionOnSet_ReturnsDataFromGetFunction()
    {
        // Arrange
        const int ExpectedId = 1;
        const string ExpectedName = "Test";
        var testData = new TestData { Id = ExpectedId, Name = ExpectedName };

        _database.StringGetAsync(Arg.Any<RedisKey>(), Arg.Any<CommandFlags>()).Returns(RedisValue.Null);
        _database.StringSetAsync(Arg.Any<RedisKey>(), Arg.Any<RedisValue>(), Arg.Any<TimeSpan?>(), Arg.Any<bool>(), Arg.Any<When>(), Arg.Any<CommandFlags>())
            .Returns<bool>(_ => throw new RedisConnectionException(ConnectionFailureType.UnableToConnect, "Connection failed"));

        Task<TestData> get() => Task.FromResult(testData);

        // Act
        var result = await _cache.GetOrAddAsync(_testKey, TimeSpan.FromMinutes(5), get);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Id, Is.EqualTo(ExpectedId));
            Assert.That(result.Name, Is.EqualTo(ExpectedName));
        }
    }

    [Test]
    public async Task GetOrAddAsync_WhenGetFunctionThrowsException_ReturnsNullWithoutPropagatingException()
    {
        // Arrange
        _database.StringGetAsync(Arg.Any<RedisKey>(), Arg.Any<CommandFlags>()).Returns(RedisValue.Null);

        static Task<TestData> get() => throw new InvalidOperationException("Get function failed");

        // Act
        var result = await _cache.GetOrAddAsync(_testKey, TimeSpan.FromMinutes(5), get);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public async Task GetOrAddAsync_WhenBothDatabaseAndGetFunctionThrow_ReturnsNullWithoutPropagatingException()
    {
        // Arrange
        _database.StringGetAsync(Arg.Any<RedisKey>(), Arg.Any<CommandFlags>())
            .Returns<RedisValue>(_ => throw new RedisConnectionException(ConnectionFailureType.UnableToConnect, "Connection failed"));

        static Task<TestData> get() => throw new InvalidOperationException("Get function also failed");

        // Act
        var result = await _cache.GetOrAddAsync(_testKey, TimeSpan.FromMinutes(5), get);

        // Assert
        Assert.That(result, Is.Null);
    }

    #endregion

    private class TestData
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
    }
}
