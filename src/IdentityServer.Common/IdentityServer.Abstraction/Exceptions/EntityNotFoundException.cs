namespace IdentityServer.Abstraction.Exceptions;

public class EntityNotFoundException : Exception
{
    public EntityNotFoundException() { }

    public EntityNotFoundException(string message) : base(message) { }

    public EntityNotFoundException(string message, Exception inner) : base(message, inner) { }
}
