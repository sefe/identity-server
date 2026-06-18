using Microsoft.AspNetCore.Components;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.AdminPortal.Web.Components.Primitive.ClientGrant;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive.ClientGrant;

[TestFixture]
public class ClientGrantEditorDtoTests : Bunit.TestContext
{
    private const string _grantType1 = ClientGrantTypeNames.Grant_Code;
    private const string _grantType2 = ClientGrantTypeNames.Grant_ClientCredentials;
    private const string _implicitGrant = ClientGrantTypeNames.Grant_Implicit;

    private static ClientPropertyGrantDtoRead CreateGrant(string grantType) => new()
    {
        Id = 1,
        ClientId = 1,
        GrantType = grantType
    };

    [Test]
    public void Render_WithInitialGrants_RendersGrantItems()
    {
        // Arrange
        var grants = new List<ClientPropertyGrantDtoRead> { CreateGrant(_grantType1), CreateGrant(_grantType2) };

        // Act
        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => { }))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => { }))
        );

        // Assert
        Assert.That(cut.Markup, Does.Contain(ClientGrantTypeNames.AllGrantTypes[_grantType1]));
        Assert.That(cut.Markup, Does.Contain(ClientGrantTypeNames.AllGrantTypes[_grantType2]));
    }

    [Test]
    public async Task AddValue_OnBeforeAddReturnsSuccess_GrantIsAddedAndValueChangedInvoked()
    {
        // Arrange
        var grants = new List<ClientPropertyGrantDtoRead>();
        var newGrant = CreateGrant(_grantType1);
        var valueChangedCalled = false;
        var onAfterUpdateCalled = false;

        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => valueChangedCalled = true))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((newGrant, true)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => onAfterUpdateCalled = true))
        );

        // Act
        await cut.Instance.AddValue(_grantType1);

        // Assert
        Assert.That(grants, Has.Count.EqualTo(1));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(grants[0].GrantType, Is.EqualTo(_grantType1));
            Assert.That(valueChangedCalled, Is.True);
            Assert.That(onAfterUpdateCalled, Is.True);
        }
    }

    [Test]
    public async Task RemoveValue_OnBeforeRemoveReturnsSuccess_GrantIsRemovedAndValueChangedInvoked()
    {
        // Arrange
        var grant = CreateGrant(_grantType1);
        var grants = new List<ClientPropertyGrantDtoRead> { grant };
        var valueChangedCalled = false;
        var onAfterUpdateCalled = false;

        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => valueChangedCalled = true))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(true))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => onAfterUpdateCalled = true))
        );

        // Act
        await cut.Instance.RemoveValue(grant);

        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(grants, Is.Empty);
            Assert.That(valueChangedCalled, Is.True);
            Assert.That(onAfterUpdateCalled, Is.True);
        }
    }

    [Test]
    public async Task RemoveValue_OnBeforeRemoveReturnsFalse_GrantIsNotRemovedAndValueChangedNotInvoked()
    {
        // Arrange
        var grant = CreateGrant(_grantType1);
        var grants = new List<ClientPropertyGrantDtoRead> { grant };
        var valueChangedCalled = false;
        var onAfterUpdateCalled = false;

        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => valueChangedCalled = true))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => onAfterUpdateCalled = true))
        );

        // Act
        await cut.Instance.RemoveValue(grant);

        using (Assert.EnterMultipleScope())
        {
            // Assert
            Assert.That(grants, Has.Count.EqualTo(1));
            Assert.That(valueChangedCalled, Is.False);
            Assert.That(onAfterUpdateCalled, Is.False);
        }
    }

    [Test]
    [TestCase(true, true)]
    [TestCase(false, false)]
    public void IncompatibleItems_WhenClientAllowsOfflineAccessAndImplicit(bool allowOfflineAccess, bool expected)
    {
        // Arrange
        var grants = new List<ClientPropertyGrantDtoRead>();
        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ClientAllowsOfflineAccess, allowOfflineAccess)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => { }))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => { }))
        );

        // Act
        var isForbidden = cut.Instance.IsForbiddenImplicitGrant(_implicitGrant);

        // Assert
        Assert.That(isForbidden, Is.EqualTo(expected));
    }

    [Test]
    [TestCase(true, ClientGrantTypeNames.Grant_Implicit, "Implicit grant is not permitted for a client with allowed Refresh Token.")]
    [TestCase(false, ClientGrantTypeNames.Grant_Implicit, "")]
    [TestCase(true, ClientGrantTypeNames.Grant_Code, "")]
    public void GetGrantTooltip_WhenCalled_ReturnsExpectedTooltip(bool clientAllowsOfflineAccess, string grantType, string expectedTooltipPart)
    {
        // Arrange
        var grants = new List<ClientPropertyGrantDtoRead>();
        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ClientAllowsOfflineAccess, clientAllowsOfflineAccess)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => { }))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => { }))
        );

        // Act
        var tooltip = cut.Instance.GetGrantTooltip(grantType);

        // Assert
        if (!string.IsNullOrEmpty(expectedTooltipPart))
        {
            Assert.That(tooltip, Does.Contain(expectedTooltipPart));
        }
        else
        {
            Assert.That(tooltip, Is.Not.Null);
        }
    }

    [Test]
    public void IsAlreadyAdded_WithExistingGrant_ReturnsTrue()
    {
        // Arrange
        const string grantType = ClientGrantTypeNames.Grant_Code;
        var grants = new List<ClientPropertyGrantDtoRead> { CreateGrant(grantType) };
        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => { }))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => { }))
        );

        // Act
        var result = cut.Instance.IsAlreadyAdded(grantType);

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void IsAlreadyAdded_WithNonExistingGrant_ReturnsFalse()
    {
        // Arrange
        const string existingGrant = ClientGrantTypeNames.Grant_Code;
        const string nonExistingGrant = ClientGrantTypeNames.Grant_ClientCredentials;
        var grants = new List<ClientPropertyGrantDtoRead> { CreateGrant(existingGrant) };
        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => { }))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => { }))
        );

        // Act
        var result = cut.Instance.IsAlreadyAdded(nonExistingGrant);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void Render_WithUnknownGrant_RendersGrantKey()
    {
        // Arrange
        var unknownGrant = "custom_grant";
        var grants = new List<ClientPropertyGrantDtoRead> { CreateGrant(unknownGrant) };

        // Act
        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => { }))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => { }))
        );

        // Assert
        Assert.That(cut.Markup, Does.Contain(unknownGrant));
    }

    [Test]
    public void Render_WithMixedKnownAndUnknownGrants_RendersBoth()
    {
        // Arrange
        var unknownGrant = "custom_grant";
        var grants = new List<ClientPropertyGrantDtoRead>
        {
            CreateGrant(_grantType1),
            CreateGrant(unknownGrant)
        };

        // Act
        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => { }))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => { }))
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
        var grants = new List<ClientPropertyGrantDtoRead> { CreateGrant(_grantType1) };

        // Act
        var cut = RenderComponent<ClientGrantEditorDto>(parameters => parameters
            .Add(p => p.Value, grants)
            .Add(p => p.ValueChanged, EventCallback.Factory.Create<List<ClientPropertyGrantDtoRead>>(this, _ => { }))
            .Add(p => p.OnBeforeAdd, _ => Task.FromResult<(ClientPropertyGrantDtoRead, bool)>((null, false)))
            .Add(p => p.OnBeforeRemove, _ => Task.FromResult(false))
            .Add(p => p.OnAfterUpdate, EventCallback.Factory.Create(this, () => { }))
        );

        // Assert
        Assert.That(cut.Markup, Does.Contain(ClientGrantTypeNames.AllGrantTypes[_grantType1]));
    }
}
