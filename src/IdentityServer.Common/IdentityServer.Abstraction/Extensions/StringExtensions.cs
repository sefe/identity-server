namespace IdentityServer.Abstraction.Extensions;

public static class StringExtensions
{
    /// <summary>
    /// Determines whether two specified strings are equal using an ordinal comparison.
    /// </summary>
    /// <remarks>This method performs a case-sensitive, culture-insensitive comparison of the two
    /// strings.</remarks>
    /// <param name="first">The first string to compare. Can be <see langword="null"/>.</param>
    /// <param name="second">The second string to compare. Can be <see langword="null"/>.</param>
    /// <returns><see langword="true"/> if the two strings are equal using an ordinal comparison; otherwise, <see
    /// langword="false"/>.</returns>
    public static bool IsSame(this string first, string second)
    {
        return string.Equals(first, second, StringComparison.Ordinal);
    }

    /// <summary>
    /// Determines whether two strings are equal, ignoring case differences.
    /// </summary>
    /// <remarks>This method performs a case-insensitive comparison using <see
    /// cref="StringComparison.OrdinalIgnoreCase"/>.</remarks>
    /// <param name="first">The first string to compare. Can be <see langword="null"/>.</param>
    /// <param name="second">The second string to compare. Can be <see langword="null"/>.</param>
    /// <returns><see langword="true"/> if the two strings are equal, ignoring case; otherwise, <see langword="false"/>.</returns>
    public static bool IsSameLax(this string first, string second)
    {
        return string.Equals(first, second, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Replaces the first occurrence of a specified substring in the input string with a new value.
    /// </summary>
    /// <param name="input">The original string where the replacement will occur.</param>
    /// <param name="oldValue">The substring to be replaced.</param>
    /// <param name="newValue">The substring to replace the first occurrence of <paramref name="oldValue"/>.</param>
    /// <returns>
    /// A new string with the first occurrence of <paramref name="oldValue"/> replaced by <paramref name="newValue"/>.
    /// If <paramref name="oldValue"/> is not found in <paramref name="input"/>, the original string is returned.
    /// </returns>
    /// <example>
    /// <code>
    /// string result = ReplaceJustOnce("papa", "pa", "ma");
    /// Console.WriteLine(result); // Output: "mapa"
    /// </code>
    /// </example>
    public static string ReplaceJustOnce(this string input, string oldValue, string newValue)
    {
        if (string.IsNullOrEmpty(input))
        {
            return input;
        }

        if (string.IsNullOrEmpty(oldValue))
        {
            throw new ArgumentException("The value to searh and replace cannot be null or empty string.", nameof(oldValue));
        }

        // Find the index of the first occurrence of oldValue
        int index = input.IndexOf(oldValue);

        // If oldValue is not found, return the original string
        if (index == -1)
        {
            return input;
        }

        // Replace the first occurrence by reconstructing the string
        string result = string.Concat(input.AsSpan(0, index), newValue, input.AsSpan(index + oldValue.Length));
        return result;
    }

    public static string FormatAsSecretPreview(this string? input)
    {
        return input + "********";
    }
}
