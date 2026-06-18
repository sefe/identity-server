namespace IdentityServer.Abstraction.Contracts;

public interface IHasPeriodData
{
    DateTime ValidFrom { get; set; }
    DateTime ValidTo { get; set; }
}
