namespace IdentityServer.Abstraction.Contracts;

public interface ISecretGeneratorService
{
    string GenerateSecureSecret();
}