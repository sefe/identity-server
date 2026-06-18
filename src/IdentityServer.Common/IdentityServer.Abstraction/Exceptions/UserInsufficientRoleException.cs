namespace IdentityServer.Abstraction.Exceptions;

public class UserInsufficientRoleException : Exception
{
    public UserInsufficientRoleException() { }

    public UserInsufficientRoleException(string message) : base(message) { }

    public UserInsufficientRoleException(string message, Exception inner) : base(message, inner) { }
}
