// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.Contracts;

public interface IHasId<TId>
{
    TId Id { get; set; }
}

/// <summary>
/// Provides equality comparison for types implementing IHasId<TId> based on their Id property.
/// </summary>
public class IdEqualityComparer<T, TId> : IEqualityComparer<T> where T : IHasId<TId>
{
    private readonly IEqualityComparer<TId> _idComparer;

    /// <summary>
    /// Creates a new instance using the default equality comparer for TId.
    /// </summary>
    public IdEqualityComparer() : this(EqualityComparer<TId>.Default)
    {
    }

    /// <summary>
    /// Creates a new instance using the specified equality comparer for TId.
    /// </summary>
    public IdEqualityComparer(IEqualityComparer<TId> idComparer)
    {
        _idComparer = idComparer ?? throw new ArgumentNullException(nameof(idComparer));
    }

    public bool Equals(T? x, T? y)
    {
        if (ReferenceEquals(x, y))
        {
            return true;
        }

        if (x is null || y is null)
        {
            return false;
        }

        return _idComparer.Equals(x.Id, y.Id);
    }

    public int GetHashCode(T? obj)
    {
        if (obj is null)
        {
            return 0;
        }

        return obj.Id is null ? 0 : _idComparer.GetHashCode(obj.Id);
    }

    /// <summary>
    /// Gets a static instance of the default comparer.
    /// </summary>
    public static IdEqualityComparer<T, TId> Default { get; } = new IdEqualityComparer<T, TId>();
}

// Static helper class for more convenient usage
public static class IdEqualityComparer
{
    /// <summary>
    /// Creates an equality comparer for the specified IHasId<TId> type.
    /// </summary>
    public static IdEqualityComparer<T, TId> For<T, TId>() where T : IHasId<TId>
    {
        return IdEqualityComparer<T, TId>.Default;
    }

    /// <summary>
    /// Creates an equality comparer for the specified IHasId<TId> type with a custom ID comparer.
    /// </summary>
    public static IdEqualityComparer<T, TId> For<T, TId>(IEqualityComparer<TId> idComparer) where T : IHasId<TId>
    {
        return new IdEqualityComparer<T, TId>(idComparer);
    }
}