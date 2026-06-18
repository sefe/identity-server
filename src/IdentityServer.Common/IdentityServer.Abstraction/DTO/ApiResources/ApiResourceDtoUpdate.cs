using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.ApiResources;

/// <summary>
/// All fields except Id are optional and nullable. Only fields to be updated must be set.
/// </summary>
public class ApiResourceDtoUpdate : IDtoUpdate
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Id must be a positive integer greater than 0")]
    public int Id { get; set; }

    [TrimmedStringLength(MaximumLength = Constants.Limits.ApiResource.DisplayName.MaxLength, MinimumLength = 1, ErrorMessage = Constants.Limits.ApiResource.DisplayName.MaxLengthError)]
    public string? DisplayName { get; set; }

    [StringLength(Constants.Limits.ApiResource.Description.MaxLength, ErrorMessage = Constants.Limits.ApiResource.Description.MaxLengthError)]
    public string? Description { get; set; }

    public bool? Enabled { get; set; }
}
