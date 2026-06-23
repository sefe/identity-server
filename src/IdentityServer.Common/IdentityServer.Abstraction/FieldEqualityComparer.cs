// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction;

using System;
using System.Collections.Generic;

public class FieldEqualityComparer<T> : IEqualityComparer<T>
    where T : class
{
    private readonly Func<T, object> _fieldSelector;

    public FieldEqualityComparer(Func<T, object> fieldSelector)
    {
        _fieldSelector = fieldSelector ?? throw new ArgumentNullException(nameof(fieldSelector));
    }

    public bool Equals(T? x, T? y)
    {
        if (x == null && y == null)
        {
            return true;
        }

        if (x == null || y == null)
        {
            return false;
        }

        var xValue = _fieldSelector(x);
        var yValue = _fieldSelector(y);

        return Equals(xValue, yValue);
    }

    public int GetHashCode(T obj)
    {
        ArgumentNullException.ThrowIfNull(obj);

        var fieldValue = _fieldSelector(obj);
        return fieldValue?.GetHashCode() ?? 0;
    }
}

public static class FieldEqualityComparer
{
    public static IEqualityComparer<T> For<T>(Func<T, object> fieldSelector)
        where T : class
    {
        return new FieldEqualityComparer<T>(fieldSelector);
    }
}
