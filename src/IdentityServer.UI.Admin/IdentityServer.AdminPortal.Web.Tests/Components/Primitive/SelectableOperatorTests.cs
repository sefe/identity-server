// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using IdentityServer.AdminPortal.Web.Components.Primitive;
using IdentityServer.Abstraction.Entities;
using Microsoft.AspNetCore.Components;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive;

[TestFixture]
public class SelectableOperatorTests : Bunit.TestContext
{
    [Test]
    public void SelectAll_SetsAllItemsSelected_AndInvokesCallback()
    {
        // Arrange
        var items = new List<Selectable> { new() { DisplayName = "Test" }, new() { DisplayName = "Test" } };
        var called = false;
        var cut = RenderComponent<SelectableOperator>(parameters => parameters
            .Add(p => p.Items, items)
            .Add(p => p.OnStateChanged, EventCallback.Factory.Create(this, () => called = true))
        );

        // Act
        cut.FindAll("button")[0].Click();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(items.TrueForAll(i => i.IsSelected), Is.True);
            Assert.That(called, Is.True);
        }
    }

    [Test]
    public void SelectNone_SetsAllItemsUnselected_AndInvokesCallback()
    {
        // Arrange
        var items = new List<Selectable> { new() { IsSelected = true, DisplayName = "Test" }, new() { IsSelected = true, DisplayName = "Test" } };
        var called = false;
        var cut = RenderComponent<SelectableOperator>(parameters => parameters
            .Add(p => p.Items, items)
            .Add(p => p.OnStateChanged, EventCallback.Factory.Create(this, () => called = true))
        );

        // Act
        cut.FindAll("button")[1].Click();

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(items.TrueForAll(i => !i.IsSelected), Is.True);
            Assert.That(called, Is.True);
        }
    }
}
