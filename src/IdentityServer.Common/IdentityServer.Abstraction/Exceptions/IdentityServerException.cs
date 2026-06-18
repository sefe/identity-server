namespace IdentityServer.Abstraction.Exceptions;

public class IdentityServerException : Exception
{
    public IdentityServerException() { }

    public IdentityServerException(string message) : base(message) { }

    public IdentityServerException(string message, Exception inner) : base(message, inner) { }
}
