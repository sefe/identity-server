using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.AdminPortal.Web.Services.Search;

public class SearchFormModel
{
    [TrimmedStringLength(MinimumLength = MinSearchSymbols, ErrorMessage = MinSearchSymbolsErrorMessage)]
    [MaxLength(MaxSearchSymbols, ErrorMessage = MaxSearchSymbolsErrorMessage)]
    public string SearchTerm { get; set; } = string.Empty;

    public const int MinSearchSymbols = 3;
    public const int MaxSearchSymbols = 50;
    public const string MinSearchSymbolsErrorMessage = "Please provide at least 3 meaningful characters for search";
    public const string MaxSearchSymbolsErrorMessage = "Please provide no more than 50 characters for search";
}
