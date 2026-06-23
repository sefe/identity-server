// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Diagnostics.CodeAnalysis;
using IdentityServer.Abstraction.Enums;

namespace IdentityServer.Abstraction.DTO.History;

/// <summary>
/// Represents a change to a single field.
/// </summary>
public class FieldChangeDto
{
    [SetsRequiredMembers]
    public FieldChangeDto(string fieldName, string? newValue, string? oldValue = null)
    {
        FieldName = fieldName;
        NewValue = newValue;
        OldValue = oldValue;
    }

    [SetsRequiredMembers]
    public FieldChangeDto(string fieldName, string? value, HistoryEventType eventType)
    {
        FieldName = fieldName;
        if (eventType == HistoryEventType.Deleted)
        {
            OldValue = value;
        }
        else
        {
            NewValue = value;
        }
    }

    public FieldChangeDto() { }

    /// <summary>
    /// Gets or sets the name of the field that changed.
    /// </summary>
    public required string FieldName { get; set; }

    /// <summary>
    /// Gets or sets the previous value of the field.
    /// </summary>
    public string? OldValue { get; set; }

    /// <summary>
    /// Gets or sets the new value of the field.
    /// </summary>
    public string? NewValue { get; set; }

    public void SwapValues()
    {
        (NewValue, OldValue) = (OldValue, NewValue);
    }
}
