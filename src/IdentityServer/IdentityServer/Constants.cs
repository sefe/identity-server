namespace IdentityServer;

public static class Constants
{
    public static class AuthenticationSchemes
    {
        public const string API_JWT_Bearer = "API_JWT";
        public const string EntraId_JWT_Bearer = "ENTRA_JWT";
    }

    public static class Policies
    {
        public const string M2MClientsRead = "M2MClientsRead";
        public const string M2MReportsRead = "M2MReportsRead";
    }
}
