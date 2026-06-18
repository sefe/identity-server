namespace IdentityServer.Abstraction.Exceptions;

public class EntityReferenceException : Exception
{
    public EntityReferenceException() { }

    public EntityReferenceException(string message) : base(message) { }

    public EntityReferenceException(string message, Exception inner) : base(message, inner) { }
}
