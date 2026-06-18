namespace IdentityServer.Data.Repositories.Storage;

public interface IParentAccessor<in TModel, in TParent>
{
    int GetParentEnvironmentId(TParent parent);
    int GetParentId(TModel model);
}
