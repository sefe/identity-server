using System.Linq.Expressions;
using IdentityServer.Abstraction.Contracts;

namespace IdentityServer.Tests.Common.Builders;

public class MockStorage<T> : StorageBase<T> where T : class
{
    public MockStorage(Expression<Func<T, int>> idExpression)
        : base(idExpression)
    {
    }

    public List<T> Items { get; set; } = new List<T>();

    public override Task<T> AddAsync(T resource)
    {
        Items.Add(resource);
        return Task.FromResult(resource);
    }

    public override Task<bool> AnyAsync(Expression<Func<T, bool>> predicate)
    {
        return Task.FromResult(Items.AsQueryable().Any(predicate));
    }

    public override Task<int> CountAsync(Expression<Func<T, bool>> predicate)
    {
        return Task.FromResult(Items.AsQueryable().Count(predicate));
    }

    public override Task<int?> DeleteAsync(T resource)
    {
        Items.Remove(resource);
        return Task.FromResult<int?>(ModelIdGetter(resource));
    }

    public override Task DeleteAsync(IEnumerable<T> resources)
    {
        foreach (var r in resources)
        {
            Items.Remove(r);
        }
        return Task.CompletedTask;
    }

    public override Task<T> FirstOrDefaultAsync(Expression<Func<T, bool>> predicate)
    {
        return Task.FromResult(Items.AsQueryable().FirstOrDefault(predicate));
    }

    public override IQueryable<T> ShallowQuery()
    {
        throw new NotImplementedException();
    }

    public override Task<List<T>> ToListAsync(Expression<Func<T, bool>> predicate)
    {
        return Task.FromResult(Items.AsQueryable().Where(predicate).ToList());
    }

    public override Task<List<T>> ToListAsync<TKey>(Expression<Func<T, bool>> predicate, Expression<Func<T, TKey>> orderBy, int skip, int take)
    {
        return Task.FromResult(Items.AsQueryable().Where(predicate).OrderBy(orderBy).Skip(skip).Take(take).ToList());
    }

    public override Task<T> UpdateAsync(T resource)
    {
        var index = Items.FindIndex(x => ModelIdGetter(x) == ModelIdGetter(resource));
        Items.RemoveAt(index);
        Items.Insert(index, resource);
        return Task.FromResult(resource);
    }
}
