using Microsoft.AspNetCore.Components;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.AdminPortal.Web.Components.Primitive.ClientGrant;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive.ClientGrant;

[TestFixture]
public class ClientGrantEditorStringTests : Bunit.TestContext
{
    private const string _grantType1 = ClientGrantTypeNames.Grant_Code;
    private const string _grantType2 = ClientGrantTypeNames.Grant_ClientCredentials;

    private static HashSet<string> CreateGrants(params string[] grants) => new(grants);

    [Test]
    public void Render_WithInitialGrants_RendersGrantItems()
    {
        // Arrange
        var grants = CreateGrants(_grantType1, _grantType2);

        // Act
        var cut = RenderComponent<ClientGrantEditorString>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<HashSet<string>>(this, _ => { }))
        );

        // Assert
        Assert.That(cut.Markup, Does.Contain(ClientGrantTypeNames.AllGrantTypes[_grantType1]));
        Assert.That(cut.Markup, Does.Contain(ClientGrantTypeNames.AllGrantTypes[_grantType2]));
    }

    [Test]
    public void AddValue_GrantIsAddedAndValueChangedInvoked()
    {
        // Arrange
        var grants = CreateGrants();
        var valueChangedCalled = false;
        var cut = RenderComponent<ClientGrantEditorString>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<HashSet<string>>(this, _ => valueChangedCalled = true))
        );

        // Act
        cut.Instance.GetType().GetMethod("AddValue", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!
            .Invoke(cut.Instance, new object[] { _grantType1 });

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(grants, Has.Count.EqualTo(1));
            Assert.That(grants, Does.Contain(_grantType1));
            Assert.That(valueChangedCalled, Is.True);
        }
    }

    [Test]
    public void RemoveValue_GrantIsRemovedAndValueChangedInvoked()
    {
        // Arrange
        var grants = CreateGrants(_grantType1);
        var valueChangedCalled = false;
        var cut = RenderComponent<ClientGrantEditorString>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<HashSet<string>>(this, _ => valueChangedCalled = true))
        );

        // Act
        cut.Instance.GetType().GetMethod("RemoveValue", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!
            .Invoke(cut.Instance, new object[] { _grantType1 });

        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(grants, Is.Empty);
            Assert.That(valueChangedCalled, Is.True);
        }
    }

    [Test]
    public void RemoveValue_GrantNotPresent_ValueChangedNotInvoked()
    {
        // Arrange
        var grants = CreateGrants(_grantType1);
        var valueChangedCalled = false;
        var cut = RenderComponent<ClientGrantEditorString>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<HashSet<string>>(this, _ => valueChangedCalled = true))
        );

        // Act
        cut.Instance.RemoveValue(_grantType2);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(grants, Has.Count.EqualTo(1));
            Assert.That(grants, Does.Contain(_grantType1));
            Assert.That(valueChangedCalled, Is.False);
        }
    }

    [Test]
    public void IsAlreadyAdded_WhenGrantExists_ReturnsTrue()
    {
        // Arrange
        var grants = CreateGrants(_grantType1);
        var cut = RenderComponent<ClientGrantEditorString>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<HashSet<string>>(this, _ => { }))
        );

        // Act
        var result = cut.Instance.IsAlreadyAdded(_grantType1);

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void IsAlreadyAdded_WhenGrantDoesNotExist_ReturnsFalse()
    {
        // Arrange
        var grants = CreateGrants(_grantType1);
        var cut = RenderComponent<ClientGrantEditorString>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<HashSet<string>>(this, _ => { }))
        );

        // Act
        var result = cut.Instance.IsAlreadyAdded(_grantType2);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void Render_WithUnknownGrant_RendersGrantKey()
    {
        // Arrange
        var unknownGrant = "custom_grant";
        var grants = CreateGrants(unknownGrant);

        // Act
        var cut = RenderComponent<ClientGrantEditorString>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<HashSet<string>>(this, _ => { }))
        );

        // Assert
        Assert.That(cut.Markup, Does.Contain(unknownGrant));
    }

    [Test]
    public void Render_WithMixedKnownAndUnknownGrants_RendersBoth()
    {
        // Arrange
        var unknownGrant = "custom_grant";
        var grants = CreateGrants(_grantType1, unknownGrant);

        // Act
        var cut = RenderComponent<ClientGrantEditorString>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<HashSet<string>>(this, _ => { }))
        );

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(cut.Markup, Does.Contain(ClientGrantTypeNames.AllGrantTypes[_grantType1]));
            Assert.That(cut.Markup, Does.Contain(unknownGrant));
        }
    }

    [Test]
    public void Render_WithKnownGrant_RendersDisplayName()
    {
        // Arrange
        var grants = CreateGrants(_grantType1);

        // Act
        var cut = RenderComponent<ClientGrantEditorString>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<HashSet<string>>(this, _ => { }))
        );

        // Assert
        Assert.That(cut.Markup, Does.Contain(ClientGrantTypeNames.AllGrantTypes[_grantType1]));
    }
}
