using System.Security.Claims;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Extensions;

namespace IdentityServer.Abstraction.Exceptions;

public class EntityAccessException : Exception
{
    private const string _messageTemplate = "{0} Access to {1} is forbidden for user {2}";
    private const string _extendedMessageTemplate = "{0} Access to {1} is forbidden for user {2}. {3}";

    public ClaimsPrincipal? User { get; private set; }
    public string? Entity { get; private set; }
    public EntityAccessType? Access { get; private set; }

    public EntityAccessException() { }

    public EntityAccessException(ClaimsPrincipal user, string entity, EntityAccessType access)
        : base(string.Format(_messageTemplate, access, entity, GetUserName(user)))
    {
        User = user;
        Entity = entity;
        Access = access;
    }

    public EntityAccessException(ClaimsPrincipal user, string entity, EntityAccessType access, Exception inner)
        : base(string.Format(_messageTemplate, access, entity, GetUserName(user)), inner)
    {
        User = user;
        Entity = entity;
        Access = access;
    }

    public EntityAccessException(ClaimsPrincipal user, string entity, EntityAccessType access, string reason)
        : base(string.Format(_extendedMessageTemplate, access, entity, GetUserName(user), reason))
    {
        User = user;
        Entity = entity;
        Access = access;
    }

    public EntityAccessException(ClaimsPrincipal user, string entity, EntityAccessType access, string reason, Exception inner)
        : base(string.Format(_extendedMessageTemplate, access, entity, GetUserName(user), reason), inner)
    {
        User = user;
        Entity = entity;
        Access = access;
    }

    private static string GetUserName(ClaimsPrincipal user) => $"{user.GetUserName()} (id: {user.GetUserObjectId()})";
}
