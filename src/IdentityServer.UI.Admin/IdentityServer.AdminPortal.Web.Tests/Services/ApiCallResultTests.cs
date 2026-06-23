// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text.Json;
using IdentityServer.AdminPortal.Web.Services;

namespace IdentityServer.AdminPortal.Web.Tests.Services;

[TestFixture]
public class ApiCallResultTests
{
    private class TestDto
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public DateTime CreatedDate { get; set; }
        public List<string> Tags { get; set; } = new();
    }

    [Test]
    public void Constructor_WithSuccessResult_InitializesCorrectly()
    {
        // Arrange
        var testData = new TestDto
        {
            Id = 1,
            Name = "Test Entity",
            CreatedDate = DateTime.UtcNow,
            Tags = new List<string> { "tag1", "tag2" }
        };

        // Act
        var apiResult = new ApiCallResult<TestDto>(testData);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(apiResult.Result, Is.EqualTo(testData));
            Assert.That(apiResult.ErrorMessage, Is.Null);
            Assert.That(apiResult.Details, Is.Null);
            Assert.That(apiResult.IsSuccess, Is.True);
        }
    }

    [Test]
    public void Constructor_WithErrorMessage_InitializesCorrectly()
    {
        // Arrange
        const string errorMessage = "Entity not found";

        // Act
        var apiResult = new ApiCallResult<TestDto>(errorMessage);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(apiResult.Result, Is.Null);
            Assert.That(apiResult.ErrorMessage, Is.EqualTo(errorMessage));
            Assert.That(apiResult.Details, Is.Null);
            Assert.That(apiResult.IsSuccess, Is.False);
        }
    }

    [Test]
    public void Constructor_WithErrorMessageAndDetails_InitializesCorrectly()
    {
        // Arrange
        const string errorMessage = "Validation failed";
        var details = new Dictionary<string, string>
        {
            ["Name"] = "Name is required",
            ["Id"] = "Id must be positive"
        };

        // Act
        var apiResult = new ApiCallResult<TestDto>(errorMessage, details);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(apiResult.Result, Is.Default);
            Assert.That(apiResult.ErrorMessage, Is.EqualTo(errorMessage));
            Assert.That(apiResult.Details, Is.EqualTo(details));
            Assert.That(apiResult.IsSuccess, Is.False);
        }
    }

    [Test]
    public void Constructor_WithNullErrorMessage_IsConsideredSuccess()
    {
        // Act
        var apiResult = new ApiCallResult<TestDto>((string)null);

        // Assert
        Assert.That(apiResult.IsSuccess, Is.True);
    }

    [Test]
    public void Constructor_WithEmptyErrorMessage_IsConsideredSuccess()
    {
        // Act
        var apiResult = new ApiCallResult<TestDto>(string.Empty);

        // Assert
        Assert.That(apiResult.IsSuccess, Is.True);
    }

    [Test]
    public void Constructor_WithWhitespaceErrorMessage_IsConsideredFailure()
    {
        // Act
        var apiResult = new ApiCallResult<TestDto>("   ");

        // Assert
        Assert.That(apiResult.IsSuccess, Is.False);
    }

    [Test]
    public void Deconstruct_ReturnsResultAndErrorMessage()
    {
        // Arrange
        const string errorMessage = "Operation failed";
        var apiResult = new ApiCallResult<TestDto>(errorMessage);

        // Act
        var (result, error) = apiResult;

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(apiResult.Result));
            Assert.That(error, Is.EqualTo(errorMessage));
        }
    }

    [Test]
    public void GetFlatErrors_WithNoDetails_ReturnsEmptyList()
    {
        // Arrange
        var apiResult = new ApiCallResult<TestDto>("Validation failed");

        // Act
        var errors = apiResult.GetFlatErrors();

        // Assert
        Assert.That(errors, Is.Null);
    }

    [Test]
    public void GetFlatErrors_WithDetailsButNoErrorsKey_ReturnsEmptyList()
    {
        // Arrange
        var details = new Dictionary<string, string>
        {
            ["info"] = "Additional information",
            ["timestamp"] = "2024-01-01T00:00:00Z"
        };
        var apiResult = new ApiCallResult<TestDto>("Operation failed", details);

        // Act
        var errors = apiResult.GetFlatErrors();

        // Assert
        Assert.That(errors, Is.Null);
    }

    [Test]
    public void GetFlatErrors_WithEmptyErrorsValue_ReturnsEmptyList()
    {
        // Arrange
        var details = new Dictionary<string, string>
        {
            ["errors"] = ""
        };
        var apiResult = new ApiCallResult<TestDto>("Validation failed", details);

        // Act
        var errors = apiResult.GetFlatErrors();

        // Assert
        Assert.That(errors, Is.Null);
    }

    [Test]
    public void GetFlatErrors_WithNullErrorsValue_ReturnsEmptyList()
    {
        // Arrange
        var details = new Dictionary<string, string>
        {
            ["errors"] = null
        };
        var apiResult = new ApiCallResult<TestDto>("Validation failed", details);

        // Act
        var errors = apiResult.GetFlatErrors();

        // Assert
        Assert.That(errors, Is.Null);
    }

    [Test]
    public void GetFlatErrors_WithValidJsonErrors_ReturnsFormattedErrors()
    {
        // Arrange
        var errorDictionary = new Dictionary<string, string[]>
        {
            ["EmptyField"] = Array.Empty<string>(),
            ["Name"] = new[] { "Name is required" },
            ["Email"] = new[] { "Email must be valid", "Email cannot be empty" },
            ["Age"] = new[] { "Age must be between 18 and 65" }
        };
        var jsonErrors = JsonSerializer.Serialize(errorDictionary);
        var details = new Dictionary<string, string>
        {
            ["errors"] = jsonErrors
        };
        var apiResult = new ApiCallResult<TestDto>("Validation failed", details);

        // Act
        var errors = apiResult.GetFlatErrors();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(errors, Has.Count.EqualTo(4));
            Assert.That(errors, Contains.Item("EmptyField: "));
            Assert.That(errors, Contains.Item("Name: Name is required"));
            Assert.That(errors, Contains.Item("Email: Email must be valid Email cannot be empty"));
            Assert.That(errors, Contains.Item("Age: Age must be between 18 and 65"));
        }
    }

    [Test]
    public void GetFlatErrors_WithInvalidJson_ReturnsEmptyList()
    {
        // Arrange
        var details = new Dictionary<string, string>
        {
            ["errors"] = "{ invalid json structure }"
        };
        var apiResult = new ApiCallResult<TestDto>("Parse error", details);

        // Act
        var errors = apiResult.GetFlatErrors();

        // Assert
        Assert.That(errors, Is.Null);
    }

    [Test]
    public void GetFlatErrors_WithJsonThatDeserializesToNull_ReturnsEmptyList()
    {
        // Arrange
        var details = new Dictionary<string, string>
        {
            ["errors"] = "null"
        };
        var apiResult = new ApiCallResult<TestDto>("Null validation result", details);

        // Act
        var errors = apiResult.GetFlatErrors();

        // Assert
        Assert.That(errors, Is.Null);
    }

    [Test]
    public void Constructor_WithNullDetailsParameter_HandlesGracefully()
    {
        // Act
        var apiResult = new ApiCallResult<TestDto>("Network error", null);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(apiResult.Details, Is.Null);
            Assert.That(apiResult.GetFlatErrors(), Is.Null);
        }
    }

    [Test]
    public void Constructor_WithEmptyDetailsParameter_HandlesGracefully()
    {
        // Arrange
        var emptyDetails = new Dictionary<string, string>();

        // Act
        var apiResult = new ApiCallResult<TestDto>("Empty details error", emptyDetails);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(apiResult.Details, Is.EqualTo(emptyDetails));
            Assert.That(apiResult.GetFlatErrors(), Is.Null);
        }
    }

    [Test]
    public void Deconstruct_WithSuccessfulResult_ReturnsDataAndNoError()
    {
        // Arrange
        var testData = new TestDto { Id = 42, Name = "Success Case" };
        var apiResult = new ApiCallResult<TestDto>(testData);

        // Act
        var (result, error) = apiResult;

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.EqualTo(testData));
            Assert.That(error, Is.Null);
        }
    }
}
