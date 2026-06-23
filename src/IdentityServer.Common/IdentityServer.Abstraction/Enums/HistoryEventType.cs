// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Enums;

/// <summary>
/// Represents the type of history event.
/// </summary>
public enum HistoryEventType
{
    /// <summary>
    /// Event type for entity creation.
    /// </summary>
    Created,

    /// <summary>
    /// Event type for entity updates.
    /// </summary>
    Updated,

    /// <summary>
    /// Event type for entity deletion.
    /// </summary>
    Deleted
}
