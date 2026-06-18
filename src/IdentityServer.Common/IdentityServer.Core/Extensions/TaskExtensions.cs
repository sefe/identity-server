namespace IdentityServer.Core.Extensions;

public static class TaskExtensions
{
    /// <summary>Returns map(Result) if not faulted or cancelled.</summary>
    public static async Task<U> Map<T, U>(this Task<T> self, Func<T, U> map)
    {
        Func<T, U> func = map;
        return func(await self);
    }
}
