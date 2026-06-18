namespace IdentityServer.AdminPortal.Web
{
    public static class StringExtensions
    {
        public static bool Match(this string? input, string compare, StringComparison comparision = StringComparison.OrdinalIgnoreCase)
            => String.Equals(input, compare, comparision);
    }
}
