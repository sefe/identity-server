// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Bunit;
using IdentityServer.AdminPortal.Web.Components.Primitive;

namespace IdentityServer.AdminPortal.Web.Tests.Components.Primitive;

[TestFixture]
public class RequiredFieldLabelTests : Bunit.TestContext
{
    [Test]
    public void RendersLabel_WithTextAndAsterisk()
    {
        // Arrange
        var labelText = "Required Field";
        var forTarget = "inputId";

        // Act
        var cut = RenderComponent<RequiredFieldLabel>(parameters => parameters
            .Add(p => p.LabelText, labelText)
            .Add(p => p.ForTarget, forTarget)
        );

        // Assert
        cut.Find("label").MarkupMatches($"<label for=\"{forTarget}\" class=\"k-label k-form-label\">{labelText}<span style=\"color:red\">&nbsp;*</span></label>");
    }
}
