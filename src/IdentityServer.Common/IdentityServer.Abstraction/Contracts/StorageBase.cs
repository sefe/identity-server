// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Linq.Expressions;

namespace IdentityServer.Abstraction.Contracts;

public abstract class StorageBase<TModel> : IStorage<TModel> where TModel : class
{
    protected StorageBase(Expression<Func<TModel, int>> idExpression)
    {
        ModelIdExpression = idExpression;
        ModelIdGetter = idExpression.Compile();
    }

    /// <summary>
    /// Expression must be translatable to SQL.
    /// </summary>
    protected Expression<Func<TModel, int>> ModelIdExpression { get; }

    protected Func<TModel, int> ModelIdGetter { get; }

    public virtual Task<TModel?> GetByIdAsync(int id) => FirstOrDefaultAsync(BuildIdEqualsExpression(id));

    private Expression<Func<TModel, bool>> BuildIdEqualsExpression(int id)
    {
        // Create a new parameter for TModel
        var parameter = Expression.Parameter(typeof(TModel), "x");
        // Replace the parameter in ModelIdExpression with the new one
        var body = Expression.Equal(
            Expression.Invoke(ModelIdExpression, parameter),
            Expression.Constant(id)
        );
        return Expression.Lambda<Func<TModel, bool>>(body, parameter);
    }

    public abstract Task<TModel> AddAsync(TModel resource);
    public abstract Task<TModel> UpdateAsync(TModel resource);
    public abstract Task<int?> DeleteAsync(TModel resource);
    public abstract Task DeleteAsync(IEnumerable<TModel> resources);
    public abstract Task<TModel?> FirstOrDefaultAsync(Expression<Func<TModel, bool>> predicate);
    public abstract Task<bool> AnyAsync(Expression<Func<TModel, bool>> predicate);
    public abstract Task<int> CountAsync(Expression<Func<TModel, bool>> predicate);
    public abstract Task<List<TModel>> ToListAsync(Expression<Func<TModel, bool>> predicate);
    public abstract Task<List<TModel>> ToListAsync<TKey>(Expression<Func<TModel, bool>> predicate, Expression<Func<TModel, TKey>> orderBy, int skip, int take);
    public abstract IQueryable<TModel> ShallowQuery();
}
