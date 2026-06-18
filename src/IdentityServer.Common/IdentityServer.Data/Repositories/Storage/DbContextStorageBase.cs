using System.Diagnostics.CodeAnalysis;
using System.Linq.Expressions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Exceptions;
using IdentityServer.Data.DbContexts;

namespace IdentityServer.Data.Repositories.Storage;

[ExcludeFromCodeCoverage]
internal abstract class DbContextStorageBase<TModel> : StorageBase<TModel> where TModel : class
{
    protected readonly IdentityServerConfigurationDbContext _dbContext;

    protected DbContextStorageBase(IdentityServerConfigurationDbContext dbContext, Expression<Func<TModel, int>> idExpression)
        : base(idExpression)
    {
        _dbContext = dbContext;
    }

    /// <summary>
    /// For Add and Remove operations.
    /// </summary>
    protected abstract DbSet<TModel> DbSet { get; }

    /// <summary>
    /// For Read operations. Override only if you need to include child entities.
    /// </summary>
    /// <returns>Queryable representation of DbSet</returns>
    protected virtual IQueryable<TModel> Query() => DbSet;

    /// <summary>
    /// For List operation. Override only if you need to include child entities for the List operation.
    /// </summary>
    /// <returns>Queryable representation of DbSet</returns>
    public override IQueryable<TModel> ShallowQuery() => DbSet;

    public override async Task<TModel> AddAsync(TModel resource)
    {
        await DbSet.AddAsync(resource);
        try
        {
            await _dbContext.SaveChangesAsync();
        }
        catch (DbUpdateException dbUpdateException)
            when (dbUpdateException.InnerException is SqlException
                && dbUpdateException.InnerException.Message.Contains("Cannot insert duplicate key row in object", StringComparison.OrdinalIgnoreCase))
        {
            throw new EntityAlreadyExistsException($"Entity of type '{typeof(TModel).Name}' with the same unique key already exists.", dbUpdateException);
        }

        return resource;
    }

    public override async Task<TModel> UpdateAsync(TModel resource)
    {
        // NB! EF docs say that the object instance obtained from GetById() is internally tracked, so it should be enough to
        // just persist whatever changes the repo applied via `_dbContext.SaveChangesAsync();` only.
        // Not verified.
        int id = ModelIdGetter(resource);
        var existingEntity = await GetByIdAsync(id) ?? throw new EntityNotFoundException($"{nameof(TModel)} with ID {id} not found.");

        _dbContext.Entry(existingEntity).CurrentValues.SetValues(resource);
        try
        {
            await _dbContext.SaveChangesAsync();
        }
        catch (DbUpdateException dbUpdateException)
            when (dbUpdateException.InnerException is SqlException
                && dbUpdateException.InnerException.Message.Contains("Cannot insert duplicate key row in object", StringComparison.OrdinalIgnoreCase))
        {
            throw new EntityAlreadyExistsException($"Entity of type '{typeof(TModel).Name}' with the same unique key already exists.", dbUpdateException);
        }
        return existingEntity;
    }

    public override async Task<int?> DeleteAsync(TModel resource)
    {
        //Task.Delay necessary to prevent rows in HistoryTable with an equal ValidFrom and ValidTo
        await Task.Delay(25);
        DbSet.Remove(resource);
        await _dbContext.SaveChangesAsync();
        return ModelIdGetter(resource);
    }

    public override async Task DeleteAsync(IEnumerable<TModel> resources)
    {
        //Task.Delay necessary to prevent rows in HistoryTable with an equal ValidFrom and ValidTo
        await Task.Delay(25);
        foreach (var r in resources)
        {
            DbSet.Remove(r);
        }
        await _dbContext.SaveChangesAsync();
    }

    public override Task<TModel?> FirstOrDefaultAsync(Expression<Func<TModel, bool>> predicate)
    {
        return Query().FirstOrDefaultAsync(predicate);
    }

    public override Task<bool> AnyAsync(Expression<Func<TModel, bool>> predicate)
    {
        return Query().AnyAsync(predicate);
    }

    public override Task<int> CountAsync(Expression<Func<TModel, bool>> predicate)
    {
        return Query().CountAsync(predicate);
    }

    public override Task<List<TModel>> ToListAsync(Expression<Func<TModel, bool>> predicate)
    {
        return ShallowQuery().Where(predicate).ToListAsync();
    }

    public override Task<List<TModel>> ToListAsync<TKey>(Expression<Func<TModel, bool>> predicate, Expression<Func<TModel, TKey>> orderBy, int skip, int take)
    {
        return ShallowQuery().Where(predicate).OrderBy(orderBy).Skip(skip).Take(take).ToListAsync();
    }
}
