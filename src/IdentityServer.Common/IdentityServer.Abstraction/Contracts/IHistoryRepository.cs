// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Security.Claims;
using IdentityServer.Abstraction.DTO.History;

namespace IdentityServer.Abstraction.Contracts;

/// <summary>
/// Generic repository for querying entity change history from temporal tables.
/// </summary>
/// <typeparam name="T">The entity type for which history is being queried.</typeparam>
public interface IHistoryRepository
{
    /// <summary>
    /// Gets the complete change history for an entity and all its nested entities.
    /// </summary>
    /// <param name="user">The user requesting the history.</param>
    /// <param name="entityId">The database ID of the entity.</param>
    /// <returns>A complete history response including all events.</returns>
    Task<HistoryResponseDto> GetHistoryAsync(ClaimsPrincipal user, int entityId);
}

public interface IApiResourceHistoryRepository : IHistoryRepository { }
public interface IClientHistoryRepository : IHistoryRepository { }
public interface ISystemPermissionHistoryRepository : IHistoryRepository { }
