namespace IdentityServer.AdminPortal.Web.Services;

public class ApiCallResult<TData>
{
    public ApiCallResult(TData result)
    {
        Result = result;
    }
    public ApiCallResult(string? errorMessage)
    {
        ErrorMessage = errorMessage;
        Result = default!;
    }

    public ApiCallResult(string? errorMessage, Dictionary<string, string>? details)
        : this(errorMessage)
    {
        if (details != null)
        {
            Details = details;
        }
    }

    public string? ErrorMessage { get; }
    public Dictionary<string, string>? Details { get; }
    public TData Result { get; }
    public bool IsSuccess => string.IsNullOrEmpty(ErrorMessage);

    public void Deconstruct(out TData result, out string? errorMessage)
    {
        result = Result;
        errorMessage = ErrorMessage;
    }

    /// <summary>
    /// Retrieves a flattened list of error messages from the "errors" field in the <see cref="Details"/> dictionary.
    /// </summary>
    /// <remarks>This method attempts to parse the "errors" field, if present, as a JSON object where keys
    /// represent error categories  and values are arrays of error messages. The resulting list contains strings
    /// formatted as "Key: Message1 Message2 ...". If the "errors" field is missing, empty, or cannot be parsed, the
    /// method returns <see langword="null"/>.</remarks>
    /// <returns>A list of formatted error messages, or <see langword="null"/> if the "errors" field is not present, empty, or
    /// invalid.</returns>
    public List<string>? GetFlatErrors()
    {
        if (Details != null && Details.TryGetValue("errors", out var errors) && !string.IsNullOrEmpty(errors))
        {
            try
            {
                var dictionary = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, string[]>>(errors);
                return dictionary?.Select(kvp => $"{kvp.Key}: {string.Join(' ', kvp.Value)}").ToList();
            }
            catch
            {
                return null;
            }
        }

        return null;
    }

    /// <summary>
    /// Creates a successful result with the specified data.
    /// </summary>
    public static ApiCallResult<TData> Success(TData result) => new(result);

    /// <summary>
    /// Creates a failed result with the specified error message.
    /// </summary>
    public static ApiCallResult<TData> Error(string errorMessage) => new(errorMessage);
}
