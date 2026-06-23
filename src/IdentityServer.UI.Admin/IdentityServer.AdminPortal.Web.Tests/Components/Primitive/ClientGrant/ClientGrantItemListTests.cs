// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using IdentityServer.AdminPortal.Web.Components.Primitive.ClientGrant;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive.ClientGrant;

[TestFixture]
public class ClientGrantItemListTests : Bunit.TestContext
{
    private const string _labelText = "Test Label";
    private const string _itemText = "Grant1";
    private const string _tooltipText = "Tooltip1";

    [Test]
    public void Renders_Label_And_None_When_Items_Is_Null()
    {
        // Arrange & Act
        var cut = RenderComponent<ClientGrantItemList>(parameters => parameters
            .Add(p => p.Label, _labelText)
            .Add(p => p.Items, null)
        );

        // Assert
        var label = cut.Find("span");
        var pill = cut.Find("div.btn-group > button:first-of-type");
        var action = cut.FindAll("div.btn-group > button:nth-of-type(2)");

        using (Assert.EnterMultipleScope())
        {
            Assert.That(action, Has.Count.Zero);
            Assert.That(label.TextContent, Is.EqualTo(_labelText));
            Assert.That(pill.TextContent, Is.EqualTo("None"));
            Assert.That(pill.Attributes["disabled"].IsSpecified, Is.True);
        }
    }

    [Test]
    public void Renders_Label_And_None_When_Items_Is_Empty()
    {
        // Arrange & Act
        var cut = RenderComponent<ClientGrantItemList>(parameters => parameters
            .Add(p => p.Label, _labelText)
            .Add(p => p.Items, Enumerable.Empty<ClientGrantItemListItem>())
        );

        // Assert
        var label = cut.Find("span");
        var pill = cut.Find("div.btn-group > button:first-of-type");
        var action = cut.FindAll("div.btn-group > button:nth-of-type(2)");

        using (Assert.EnterMultipleScope())
        {
            Assert.That(action, Has.Count.Zero);
            Assert.That(label.TextContent, Is.EqualTo(_labelText));
            Assert.That(pill.TextContent, Is.EqualTo("None"));
            Assert.That(pill.Attributes["disabled"].IsSpecified, Is.True);
        }
    }

    [Test]
    public void Renders_PillButtons_For_Each_Item()
    {
        // Arrange
        var items = new List<ClientGrantItemListItem>
        {
            new() { Text = _itemText, Tooltip = _tooltipText },
            new() { Text = "Grant2", Tooltip = null, IsReadonly = true }
        };

        // Act
        var cut = RenderComponent<ClientGrantItemList>(parameters => parameters
            .Add(p => p.Label, _labelText)
            .Add(p => p.Items, items)
        );

        // Assert
        var pillButtons = cut.FindAll("div.btn-group");
        Assert.That(pillButtons, Has.Count.EqualTo(2));
        using (Assert.EnterMultipleScope())
        {
            Assert.That(pillButtons[0].FirstElementChild.TextContent, Is.EqualTo(_itemText));
            Assert.That(pillButtons[0].GetAttribute("title"), Is.EqualTo(_tooltipText));
            Assert.That(pillButtons[1].ChildElementCount, Is.EqualTo(1));
            Assert.That(pillButtons[1].FirstElementChild.Attributes["disabled"].IsSpecified, Is.True);
        }
    }

    [Test]
    public void IsAdd_Parameter_Is_Passed_To_PillButton()
    {
        // Arrange
        var items = new[]
        {
            new ClientGrantItemListItem { Text = _itemText }
        };

        // Act
        var cut = RenderComponent<ClientGrantItemList>(parameters => parameters
            .Add(p => p.Label, _labelText)
            .Add(p => p.Items, items)
            .Add(p => p.IsAdd, true)
        );

        // Assert
        var action = cut.Find("div.btn-group > button:nth-of-type(2)");
        using (Assert.EnterMultipleScope())
        {
            Assert.That(action.TextContent, Is.EqualTo("+"));
            Assert.That(action.Attributes["disabled"], Is.Null);
        }
    }

    [Test]
    public void IsReadonly_Parameter_Overrides_Item_IsReadonly()
    {
        // Arrange
        var items = new[]
        {
            new ClientGrantItemListItem { Text = _itemText, IsReadonly = false }
        };

        // Act
        var cut = RenderComponent<ClientGrantItemList>(parameters => parameters
            .Add(p => p.Label, _labelText)
            .Add(p => p.Items, items)
            .Add(p => p.IsReadonly, true)
        );

        // Assert
        var pill = cut.Find("div.btn-group > button:first-of-type");
        var action = cut.FindAll("div.btn-group > button:nth-of-type(2)");
        using (Assert.EnterMultipleScope())
        {
            Assert.That(pill.Attributes["disabled"].IsSpecified, Is.True);
            Assert.That(action, Has.Count.Zero);
        }
    }
}
