namespace IdentityServer.Abstraction.Exceptions;

public class InvalidSearchValueException : Exception
{
    public InvalidSearchValueException() { }

    public InvalidSearchValueException(string message) : base(message) { }

    public InvalidSearchValueException(string message, Exception inner) : base(message, inner) { }
}
