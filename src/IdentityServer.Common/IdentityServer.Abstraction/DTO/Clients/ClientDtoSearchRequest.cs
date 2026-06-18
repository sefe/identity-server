using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.DTO.Clients;

public class ClientDtoSearchRequest
{
    [Required]
    [TrimmedStringLength(MinimumLength = 3, ErrorMessage = "Search Term must be at least 3 symbols long.")]
    [MaxLength(200, ErrorMessage = "Search Term is too long.")]
    public required string SearchTerm { get; set; }

    [Range(1, int.MaxValue, ErrorMessage = "Page must be a positive integer greater than 0.")]
    [DefaultValue(1)]
    public int Page { get; set; } = 1;

    [Range(1, 100, ErrorMessage = "Page Size must be in the range between 1 and 100.")]
    [DefaultValue(10)]
    public int PageSize { get; set; } = 10;
}
