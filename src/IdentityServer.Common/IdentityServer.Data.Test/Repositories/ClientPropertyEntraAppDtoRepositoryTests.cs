using AutoMapper;
using NSubstitute;
using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Contracts.MicrosoftGraph;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.EntraEntities;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Repositories.DtoRepositories.Client;
using IdentityServer.Data.Repositories.Storage;
using IdentityServer.Tests.Common.Builders;

namespace IdentityServer.Data.Test.Repositories;

[TestFixture]
public class ClientPropertyEntraAppDtoRepositoryTests
{
    private IStorage<ClientExt> _clientStorage;
    private IStorage<ClientEntraApp> _propertyStorage;
    private IMapper _mapper;
    private IPermissionChecker _permissionChecker;
    private IParentAccessor<ClientEntraApp, ClientExt> _parentAccessor;
    private IEntraApplicationService _entraAppService;
    private ClientPropertyEntraAppDtoRepository _sut;
    private ClaimsPrincipal _user;
    private ClientExt _client;

    private const int _clientId = 99;
    private const string _testAppId = "12345678-1234-1234-1234-123456789012";
    private const string _testAppName = "Test Entra App";

    [SetUp]
    public void SetUp()
    {
        _clientStorage = Substitute.For<IStorage<ClientExt>>();
        _propertyStorage = Substitute.For<IStorage<ClientEntraApp>>();
        _mapper = Substitute.For<IMapper>();
        _permissionChecker = Substitute.For<IPermissionChecker>();
        _parentAccessor = Substitute.For<IParentAccessor<ClientEntraApp, ClientExt>>();
        _entraAppService = Substitute.For<IEntraApplicationService>();
        _sut = new ClientPropertyEntraAppDtoRepository(
            _clientStorage,
            _propertyStorage,
            _mapper,
            _permissionChecker,
            _parentAccessor,
            _entraAppService
        );
        _user = new ClaimsPrincipal();
        _client = new ClientExtBuilder("test-client", "Test Client")
            .WithId(_clientId)
            .Build();
    }

    [Test]
    public async Task CreateAsync_WithValidEntraApp_CreatesMapping()
    {
        // Arrange
        var createDto = new ClientPropertyEntraAppDtoCreate
        {
            ClientId = _clientId,
            AppId = _testAppId
        };
        var propertyToCreate = new ClientEntraApp
        {
            ClientId = _clientId,
            AppId = _testAppId,
            AppName = string.Empty
        };
        var entraApp = new Application
        {
            Id = "object-id-123",
            AppId = _testAppId,
            DisplayName = _testAppName
        };
        var createdProperty = new ClientPropertyEntraAppDtoRead
        {
            Id = 1,
            ClientId = _clientId,
            AppId = _testAppId,
            AppName = _testAppName,
            Created = DateTime.UtcNow,
            CreatedBy = "test-user"
        };

        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientEntraApp, bool>>>())
            .Returns((ClientEntraApp)null);
        _mapper.Map<ClientEntraApp>(createDto).Returns(propertyToCreate);
        _entraAppService.GetByIdAsync(_testAppId).Returns(entraApp);
        _propertyStorage.AddAsync(propertyToCreate).Returns(propertyToCreate);
        _mapper.Map<ClientPropertyEntraAppDtoRead>(propertyToCreate).Returns(createdProperty);

        // Act
        var result = await _sut.CreateAsync(_user, createDto);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.ClientId, Is.EqualTo(_clientId));
            Assert.That(result.AppId, Is.EqualTo(_testAppId));
            Assert.That(result.AppName, Is.EqualTo(_testAppName));
            Assert.That(propertyToCreate.AppName, Is.EqualTo(_testAppName), "AppName should be set from EntraID");
        }
        await _entraAppService.Received(1).GetByIdAsync(_testAppId);
        await _propertyStorage.Received(1).AddAsync(propertyToCreate);
    }

    [Test]
    public void CreateAsync_WithNonExistentEntraApp_ThrowsEntityNotFoundException()
    {
        // Arrange
        var createDto = new ClientPropertyEntraAppDtoCreate
        {
            ClientId = _clientId,
            AppId = _testAppId
        };
        var propertyToCreate = new ClientEntraApp
        {
            ClientId = _clientId,
            AppId = _testAppId,
            AppName = string.Empty
        };

        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _propertyStorage.FirstOrDefaultAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientEntraApp, bool>>>())
            .Returns((ClientEntraApp)null);
        _mapper.Map<ClientEntraApp>(createDto).Returns(propertyToCreate);
        _entraAppService.GetByIdAsync(_testAppId).Returns((Application)null);

        // Act & Assert
        Assert.ThrowsAsync<EntityNotFoundException>(async () => await _sut.CreateAsync(_user, createDto));
    }

    [Test]
    public void CreateAsync_WithDuplicateEntraApp_ThrowsEntityAlreadyExistsException()
    {
        // Arrange
        var createDto = new ClientPropertyEntraAppDtoCreate
        {
            ClientId = _clientId,
            AppId = _testAppId
        };
        var existingProperty = new ClientEntraApp
        {
            Id = 1,
            ClientId = _clientId,
            AppId = _testAppId,
            AppName = _testAppName
        };
        var entraApp = new Application
        {
            Id = "object-id-123",
            AppId = _testAppId,
            DisplayName = _testAppName
        };

        _entraAppService.GetByIdAsync(_testAppId).Returns(entraApp);
        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _propertyStorage.ToListAsync(Arg.Any<System.Linq.Expressions.Expression<Func<ClientEntraApp, bool>>>())
            .Returns(new List<ClientEntraApp> { existingProperty });

        // Act & Assert
        Assert.ThrowsAsync<EntityAlreadyExistsException>(async () => await _sut.CreateAsync(_user, createDto));
    }

    [Test]
    [TestCase(_testAppId)]
    [TestCase("invalid guid")]
    public async Task DeleteAsync_RemovesMapping(string appId)
    {
        // Arrange
        const int propertyId = 1;
        var propertyToDelete = new ClientEntraApp
        {
            Id = propertyId,
            ClientId = _clientId,
            AppId = appId,
            AppName = _testAppName
        };

        _clientStorage.GetByIdAsync(_clientId).Returns(_client);
        _parentAccessor.GetParentId(propertyToDelete).Returns(_clientId);
        _propertyStorage.GetByIdAsync(propertyId).Returns(propertyToDelete);
        _propertyStorage.DeleteAsync(propertyToDelete).Returns(1);

        // Act
        await _sut.DeleteAsync(_user, propertyId);

        // Assert
        await _propertyStorage.Received(1).DeleteAsync(propertyToDelete);
    }
}
