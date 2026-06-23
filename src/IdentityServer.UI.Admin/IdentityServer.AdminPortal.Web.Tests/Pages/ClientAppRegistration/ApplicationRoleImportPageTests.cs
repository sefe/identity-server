// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Net;
using System.Text.Json;
using Bunit;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using NSubstitute;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.DTO.Export;
using IdentityServer.Abstraction.DTO.Import;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Web.Models.RoleImport;
using IdentityServer.AdminPortal.Web.Pages.ClientAppRegistration;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.Tests.Common;
using TestContext = Bunit.TestContext;

namespace IdentityServer.AdminPortal.Web.Tests.Pages.ClientAppRegistration;

[TestFixture]
public class ApplicationRoleImportPageTests
{
    // bUnit automatically provides a proper NavigationManager implementation that works correctly with Blazor components

    private TestContext _ctx;
    private IAdminApiService _adminApiService;
    private NotificationService _mockNotificationService;
    private IConfirmationService _mockConfirmationService;
    private MockHttpMultiMessageHandler _mockMultiHandler;
    private MockHttpMessageHandler _mockHandler;
    private HttpClient _mockHttpClient;

    [SetUp]
    public void Setup()
    {
        _ctx = new TestContext();
        SetupCommonServices();
    }

    [TearDown]
    public void TearDown()
    {
        _ctx.Dispose();
        _mockHttpClient?.Dispose();
        _mockHandler?.Dispose();
        _mockMultiHandler?.Dispose();
    }

    [Test]
    public void Render_WithNoApplication_ShowsLoadingMessage()
    {
        // Arrange
        // Don't setup any HTTP response, which will cause Application to remain null

        // Act
        var cut = _ctx.RenderComponent<ApplicationRoleImportPage>(parameters => parameters
            .Add(p => p.ApplicationId, 1));

        // Assert
        Assert.That(cut.Markup, Does.Contain("<p><em>Loading...</em></p>"));
    }

    [Test]
    public void Render_WithValidApplication_ShowsApplicationNameAndImportWizard()
    {
        // Arrange
        var testClient = CreateTestClient();
        SetupGetClientResponse(HttpStatusCode.OK, testClient);

        // Act
        var cut = _ctx.RenderComponent<ApplicationRoleImportPage>(parameters => parameters
            .Add(p => p.ApplicationId, testClient.Id));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Not.Contain("<p><em>Loading...</em></p>"));
            Assert.That(cut.Markup, Does.Contain($"Import Role Mappings for Application '{testClient.ClientName}'"));
            Assert.That(cut.Markup, Does.Contain("Back to the Application"));
        }
    }

    [Test]
    public async Task ValidateImportClientRoles_WithSuccessfulValidation_UpdatesImportModelWithSuccessStatus()
    {
        // Arrange
        var testClient = CreateTestClient();
        var successOperationStatus = new OperationStatus { IsCompleted = true };
        var importModel = CreateTestImportModel();

        SetupMultipleHttpResponses(testClient, successOperationStatus);

        var cut = _ctx.RenderComponent<ApplicationRoleImportPage>(parameters => parameters
            .Add(p => p.ApplicationId, testClient.Id));

        // Wait for the component to load the application
        await cut.InvokeAsync(async () => await Task.Delay(100));

        // Act
        await cut.InvokeAsync(async () => await cut.Instance.ValidateImportClientRoles(importModel));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(importModel.FileDataValidationStatus, Is.Not.Null);
            Assert.That(importModel.FileDataValidationStatus.IsCompleted, Is.True);
            Assert.That(importModel.FileDataValidationStatus.HasErrors, Is.False);
            Assert.That(importModel.FileDataValidationStatus.Errors, Has.Count.EqualTo(0));
        }
    }

    [Test]
    public async Task ValidateImportClientRoles_WithValidationErrors_UpdatesImportModelWithErrors()
    {
        // Arrange
        var testClient = CreateTestClient();
        var errorOperationStatus = new OperationStatus
        {
            IsCompleted = false,
            Errors = { "Role validation failed", "Duplicate role names found" }
        };
        var importModel = CreateTestImportModel();

        SetupMultipleHttpResponses(testClient, errorOperationStatus);

        var cut = _ctx.RenderComponent<ApplicationRoleImportPage>(parameters => parameters
            .Add(p => p.ApplicationId, testClient.Id));

        // Wait for the component to load the application
        await cut.InvokeAsync(async () => await Task.Delay(100));

        // Act
        await cut.InvokeAsync(async () => await cut.Instance.ValidateImportClientRoles(importModel));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(importModel.FileDataValidationStatus, Is.Not.Null);
            Assert.That(importModel.FileDataValidationStatus.IsCompleted, Is.False);
            Assert.That(importModel.FileDataValidationStatus.HasErrors, Is.True);
            Assert.That(importModel.FileDataValidationStatus.Errors, Has.Count.EqualTo(2));
            Assert.That(importModel.FileDataValidationStatus.Errors, Does.Contain("Role validation failed"));
            Assert.That(importModel.FileDataValidationStatus.Errors, Does.Contain("Duplicate role names found"));
        }
    }

    [Test]
    public async Task ValidateImportClientRoles_WithApiCallFailureAndFlatErrors_UpdatesImportModelWithErrors()
    {
        // Arrange
        var testClient = CreateTestClient();
        var errorOperationStatus = new ProblemDetails()
        {
            Status = 400,
            Title = "Validation Error",
            Detail = "One or more validation errors occurred.",
            Extensions = new Dictionary<string, object>
            {
                { "errors", new Dictionary<string, List<string>> {
                    { "Roles[0].RoleName", new List<string>() { "Name too long", "Dots are not allowed" } },
                    { "Roles[1].RoleName", new List<string>() { "Name too short", "Name cannot be empty" } }
                }},
                { "tradeId", "123" }
            }
        };
        var importModel = CreateTestImportModel();

        SetupMultipleHttpResponses(testClient, errorOperationStatus, HttpStatusCode.BadRequest);

        var cut = _ctx.RenderComponent<ApplicationRoleImportPage>(parameters => parameters
            .Add(p => p.ApplicationId, testClient.Id));

        // Wait for the component to load the application
        await cut.InvokeAsync(async () => await Task.Delay(100));

        // Act
        await cut.InvokeAsync(async () => await cut.Instance.ValidateImportClientRoles(importModel));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(importModel.FileDataValidationStatus, Is.Not.Null);
            Assert.That(importModel.FileDataValidationStatus.IsCompleted, Is.False);
            Assert.That(importModel.FileDataValidationStatus.HasErrors, Is.True);
            Assert.That(importModel.FileDataValidationStatus.Errors, Has.Count.EqualTo(3));
            Assert.That(importModel.FileDataValidationStatus.Errors, Does.Contain("Validation Error: One or more validation errors occurred. (HTTP 400)"));
            Assert.That(importModel.FileDataValidationStatus.Errors, Does.Contain("Roles[0].RoleName: Name too long Dots are not allowed"));
            Assert.That(importModel.FileDataValidationStatus.Errors, Does.Contain("Roles[1].RoleName: Name too short Name cannot be empty"));
        }
    }

    [Test]
    public async Task ValidateImportClientRoles_WithApiCallFailureAndNoErrors_UpdatesImportModelWithErrors()
    {
        // Arrange
        var testClient = CreateTestClient();
        var errorOperationStatus = new ProblemDetails()
        {
            Status = 500,
            Title = "Internal Server Error",
            Detail = "Unexpected errors occurred.",
            Extensions = new Dictionary<string, object>
            {
                { "activity", "456" },
                { "traceId", "123" }
            }
        };
        var importModel = CreateTestImportModel();

        SetupMultipleHttpResponses(testClient, errorOperationStatus, HttpStatusCode.BadRequest);

        var cut = _ctx.RenderComponent<ApplicationRoleImportPage>(parameters => parameters
            .Add(p => p.ApplicationId, testClient.Id));

        // Wait for the component to load the application
        await cut.InvokeAsync(async () => await Task.Delay(100));

        // Act
        await cut.InvokeAsync(async () => await cut.Instance.ValidateImportClientRoles(importModel));

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(importModel.FileDataValidationStatus, Is.Not.Null);
            Assert.That(importModel.FileDataValidationStatus.IsCompleted, Is.False);
            Assert.That(importModel.FileDataValidationStatus.HasErrors, Is.True);
            Assert.That(importModel.FileDataValidationStatus.Errors, Has.Count.EqualTo(3));
            Assert.That(importModel.FileDataValidationStatus.Errors, Does.Contain("Internal Server Error: Unexpected errors occurred. (HTTP 500)"));
            Assert.That(importModel.FileDataValidationStatus.Errors, Does.Contain("activity: 456"));
            Assert.That(importModel.FileDataValidationStatus.Errors, Does.Contain("traceId: 123"));
        }
    }

    private void SetupCommonServices()
    {
        _mockNotificationService = Substitute.For<NotificationService>();
        _mockConfirmationService = Substitute.For<IConfirmationService>();

        // Setup HttpClientFactory - not found by default
        SetupGetClientResponse(HttpStatusCode.NotFound, null);

        // Setup authentication required for UserRoleBasePage
        SetupAuthentication();

        // Setup logging required for RoleImportWizard - use LoggerFactory approach to avoid generic type issues
        var mockLoggerFactory = Substitute.For<ILoggerFactory>();
        var mockLogger = Substitute.For<ILogger>();
        mockLoggerFactory.CreateLogger(Arg.Any<string>()).Returns(mockLogger);

        _ctx.Services.AddSingleton(_mockNotificationService);
        _ctx.Services.AddSingleton(_mockConfirmationService);
        _ctx.Services.AddSingleton(mockLoggerFactory);

        // Setup common JSInterop for Telerik components
        SetupCommonInterop(_ctx);
    }

    private void SetupAuthentication()
    {
        var authState = new AuthenticationState(TestUser.Admin);
        var mockAuthStateProvider = Substitute.For<AuthenticationStateProvider>();
        mockAuthStateProvider.GetAuthenticationStateAsync().Returns(Task.FromResult(authState));
        _ctx.Services.AddSingleton(mockAuthStateProvider);
    }

    private void SetupGetClientResponse(HttpStatusCode statusCode, ClientDtoRead client)
    {
        var json = client == null ? "{}" : JsonSerializer.Serialize(client);
        _mockHandler = new MockHttpMessageHandler(statusCode, json);
        _mockHttpClient = new HttpClient(_mockHandler)
        {
            BaseAddress = new Uri("https://localhost/")
        };

        var mockHttpClientFactory = Substitute.For<IHttpClientFactory>();
        mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(_mockHttpClient);
        _adminApiService = new AdminApiService(mockHttpClientFactory);

        _ctx.Services.AddSingleton(_adminApiService);
    }

    private void SetupMultipleHttpResponses(ClientDtoRead client, object importValidationResult = null, HttpStatusCode httpStatusCode = HttpStatusCode.OK)
    {
        var responses = new List<(HttpStatusCode StatusCode, object Response)>
        {
            (HttpStatusCode.OK, client), // First response: GetClient
            (httpStatusCode, importValidationResult) // Second response: ValidateImportClientRoles
        };

        _mockMultiHandler = new MockHttpMultiMessageHandler(responses);
        _mockHttpClient = new HttpClient(_mockMultiHandler)
        {
            BaseAddress = new Uri("https://localhost/")
        };

        var mockHttpClientFactory = Substitute.For<IHttpClientFactory>();
        mockHttpClientFactory.CreateClient(AdminApiService.HttpClientName).Returns(_mockHttpClient);
        _adminApiService = new AdminApiService(mockHttpClientFactory);

        _ctx.Services.AddSingleton(_adminApiService);
    }

    private static void SetupCommonInterop(TestContext ctx)
    {
        // Setup basic JSInterop for Telerik components that might be used
        ctx.JSInterop.SetupVoid("TelerikBlazor.setOptions", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.initStepper", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.initDropZone", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.initFileSelect", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.initWizard", _ => true);
        ctx.JSInterop.SetupVoid("TelerikBlazor.initNavigationLock", _ => true);
        ctx.JSInterop.Setup<string>("TelerikBlazor.getTimezoneOffset", _ => true).SetResult("0");
        ctx.JSInterop.Setup<string>("TelerikBlazor.getTimezone", _ => true).SetResult("UTC");
    }

    private static ClientDtoRead CreateTestClient()
    {
        return new ClientDtoRead
        {
            Id = 1,
            ClientId = "test-client",
            ClientName = "Test Application",
            Description = "Test Description",
            Enabled = true,
            AccessLevel = SystemPermissionRoleType.Reader,
            SystemPermissionId = 1,
            SystemPermissionName = "Test Permission",
            SystemPermissionEnvironmentId = 1,
            SystemPermissionEnvironmentName = "Test Environment",
            Roles = new List<ClientPropertyRoleDtoRead>()
        };
    }

    private static ClientRoleImportModel CreateTestImportModel()
    {
        var importDto = new ClientRoleImportDto
        {
            ImportStrategy = ImportStrategy.Add,
            Roles = new List<RoleValueObject<ClientRoleMappingValueObject>>
            {
                new()
                {
                    RoleName = "TestRole",
                    Mappings = new List<ClientRoleMappingValueObject>
                    {
                        new() { MappingType = "UserObjectId", Value = "test-user-id", Description = "Test mapping" }
                    }
                }
            }
        };

        return new ClientRoleImportModel
        {
            FileParsingStatus = new OperationStatus<ClientRoleImportDto> { Result = importDto, IsCompleted = true },
            FileDataValidationStatus = new OperationStatus()
        };
    }
}
