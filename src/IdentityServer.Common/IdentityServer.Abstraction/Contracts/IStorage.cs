using System.Linq.Expressions;

namespace IdentityServer.Abstraction.Contracts;

public interface IStorage<TModel> where TModel : class
{
    Task<TModel?> GetByIdAsync(int id);
    Task<TModel> AddAsync(TModel resource);
    Task<TModel> UpdateAsync(TModel resource);
    Task<int?> DeleteAsync(TModel resource);
    Task DeleteAsync(IEnumerable<TModel> resources);

    Task<TModel?> FirstOrDefaultAsync(Expression<Func<TModel, bool>> predicate);
    Task<bool> AnyAsync(Expression<Func<TModel, bool>> predicate);
    Task<int> CountAsync(Expression<Func<TModel, bool>> predicate);
    Task<List<TModel>> ToListAsync(Expression<Func<TModel, bool>> predicate);
    Task<List<TModel>> ToListAsync<TKey>(Expression<Func<TModel, bool>> predicate, Expression<Func<TModel, TKey>> orderBy, int skip, int take);

    IQueryable<TModel> ShallowQuery();
}
