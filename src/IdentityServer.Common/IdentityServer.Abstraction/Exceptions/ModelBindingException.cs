namespace IdentityServer.Abstraction.Exceptions;

public class ModelBindingException : Exception
{
    public ModelBindingException()
    {
    }

    public ModelBindingException(string? message) : base(message)
    {
    }

    public ModelBindingException(string? message, Exception? innerException) : base(message, innerException)
    {
    }
}
