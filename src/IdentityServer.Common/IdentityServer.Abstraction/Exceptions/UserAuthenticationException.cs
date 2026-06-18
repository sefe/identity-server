namespace IdentityServer.Abstraction.Exceptions;

public class UserAuthenticationException : Exception
{
    public UserAuthenticationException() { }

    public UserAuthenticationException(string message) : base(message) { }

    public UserAuthenticationException(string message, Exception inner) : base(message, inner) { }
}
