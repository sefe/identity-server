using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Abstraction.Configs;

public class SecretExpirationConfig
{
    public const string SectionName = "SecretExpiration";

    [Range(1, 99, ErrorMessage = "MaxValidityYears must be between 1 and 99.")]
    public int MaxValidityYears { get; set; } = 3;

    public int DaysBeforeExpirationNotification { get; set; } = 60;
}
