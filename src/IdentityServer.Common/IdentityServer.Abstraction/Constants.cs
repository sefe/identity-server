// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction;

public static class Constants
{
    public static class EnvironmentNames
    {
        public const string Production = "PR";
        public const string PreProduction = "PP";
    }

    /// <summary>
    /// Well-known Clients.
    /// </summary>
    public static class ClientIds
    {
        public static readonly string IdentityServerAdminUi = "identityserver.admin";
        public static readonly string IdentityServerClientUi = "identityserver.client";
    }

    /// <summary>
    /// Well-known API Resources.
    /// </summary>
    public static class ApiResourceIds
    {
        public static readonly string IdentityServerApi = "identityserver";
    }

    /// <summary>
    /// Well-known token types.
    /// </summary>
    public static class TokenTypes
    {
        public static readonly string AccessToken = "urn:ietf:params:oauth:token-type:access_token";
    }

    /// <summary>
    /// Convention for non-default claim names issued by DIS
    /// </summary>
    public static class ClaimNames
    {
        public static readonly string UserDisplayName = "name";
        public static readonly string UserEmail = "email";
        public static readonly string UserObjectId = "oid";
        public static readonly string UserSubjectId = "sub";
        public static readonly string UserPrincipalName = "upn";
        public static readonly string UserRole = "role";
        public static readonly string UserOnPremisesSamAccountName = "samAccountName";
        public static readonly string UserGroups = "groups";
        public static readonly string SubjectId = "sub";

        public static readonly string Scope = "scope";
        public static readonly string M2M = "m2m";
    }

    /// <summary>
    /// Well-known scope names for IdentityServer APIs
    /// </summary>
    public static class ScopeNames
    {
        /// <summary>
        /// Used by DIS UI API.
        /// </summary>
        public static readonly string IdentityServerAdmin = "identityserver.admin";
        /// <summary>
        /// Used by DIS API.
        /// </summary>
        public static readonly string IdentityServerClientsRead = "identityserver.clients.read";
        /// <summary>
        /// Used by DIS API.
        /// </summary>
        public static readonly string IdentityServerReportsRead = "identityserver.reports.read";
    }

    public static class TokenExchange
    {
        public const string SubjectToken = "subject_token";
        public const string SubjectTokenType = "subject_token_type";
        public const string ActorToken = "actor_token";
        public const string ActorTokenType = "actor_token_type";
        public const string IdentityProvider = "tokenexchange";
        public const char ScopeSeparator = ' ';
        public const int MaxAccessTokenLifetimeSeconds = 3600 * 24 * 3; // 3 days
        public const string AccessTokenLifetimeTemporaryClaimName = "access_token_lifetime";
        public const int MaxSubjectTokenLength = 4096;
        public const int MaxActorTokenLength = 4096;
    }

    /// <summary>
    /// Claim names issued by Entra ID
    /// </summary>
    public static class ClaimNamesEntra
    {
        public static readonly string UserGroups = "groups";
        public static readonly string ClientId = "appid";
        public static readonly string Scope = "scp";
    }

    /// <summary>
    /// Scope names registered in Entra ID
    /// </summary>
    public static class ScopeNamesEntra
    {
        /// <summary>
        /// IdentityServer API scope for token exchange.
        /// </summary>
        public const string IdentityServerTokenExchangeScope = "token_exchange";
    }

    /// <summary>
    /// For Serilog
    /// </summary>
    public static class CustomContextFields
    {
        public const string Endpoint = "endpoint";
        public const string SourceIp = "source_ip";
        public const string ClientId = "client_id";
        public const string Username = "user";
        public const string SubjectId = "subject_id";
        public const string AuthMethod = "auth_method";
        public const string GrantType = "grant_type";
        public const string CorrelationId = "correlation_id";
        public const string Referer = "referer";
        public const string RequestBody = "request_body";
    }

    /// <summary>
    /// IdentityServer Admin API Roles
    /// </summary>
    public static class RoleNames
    {
        public const string Reader = "Reader";
        public const string User = "User";
        public const string Admin = "Admin";
    }

    public static class Limits
    {
        public static class Client
        {
            public static class Name
            {
                public const int MaxLength = 50;
                public const string MaxLengthError = "Identifier cannot exceed 50 characters.";
                public const string Pattern = "^[a-z0-9-]*$";
                public const string PatternInfo = "Use lowercase letters (a-z), digits (0-9), and hyphens.";
                public const string PatternError = "Only lowercase letters, digits, and hyphens are allowed.";
            }
            public static class DisplayName
            {
                public const int MaxLength = 100;
                public const string MaxLengthError = "Display name cannot be empty or exceed 100 characters.";
            }
            public static class Description
            {
                public const int MaxLength = 1000;
                public const string MaxLengthError = "Description cannot exceed 1000 characters.";
            }
        }
        public static class ApiResource
        {
            public static class Name
            {
                public const int MaxLength = 50;
                public const string MaxLengthError = "Identifier cannot exceed 50 characters.";
                public const string Pattern = "^[a-z0-9-]*$";
                public const string PatternInfo = "Use lowercase letters (a-z), digits (0-9), and hyphens.";
                public const string PatternError = "Only lowercase letters, digits, and hyphens are allowed.";
            }
            public static class DisplayName
            {
                public const int MaxLength = 100;
                public const string MaxLengthError = "Display name cannot be empty or exceed 100 characters.";
            }
            public static class Description
            {
                public const int MaxLength = 1000;
                public const string MaxLengthError = "Description cannot exceed 1000 characters.";
            }
        }
        public static class Role
        {
            public static class Name
            {
                public const int MaxLength = 50;
                public const string MaxLengthError = "Role Name must be between 1 and 50 characters long.";
                public const string Pattern = "^[a-zA-Z0-9 ]+$";
                public const string PatternInfo = "Use letters (a-z, A-Z), digits (0-9), and spaces.";
                public const string PatternError = "Only letters, digits, and spaces are allowed.";
            }
        }
        public static class RoleMapping
        {
            public static class Value
            {
                public const int MaxLength = 50;
                public const string MaxLengthError = "Role Mapping value must be between 1 and 50 characters long.";
            }
            public static class Description
            {
                public const int MaxLength = 400;
                public const string MaxLengthError = "Role Mapping Description cannot exceed 400 characters.";
            }
        }
        public static class ApiScope
        {
            public static class Name
            {
                public const int MaxLength = 149; // 50 API Resource Name + 1 dot, 200 chars DB column limit
                public const string MaxLengthError = "Scope Identifier must be between 1 and 149 characters long.";
                public const string Pattern = "^[a-z0-9-.]*$";
                public const string PatternInfo = "Use lowercase letters (a-z), digits (0-9), dots, and hyphens.";
                public const string PatternError = "Only lowercase letters, digits, dots, and hyphens are allowed.";
            }
            public static class DisplayName
            {
                public const int MaxLength = 200;
                public const string LengthRangeError = "Scope Display Name must be between 1 and 200 characters long.";
            }
            public static class Description
            {
                public const int MaxLength = 1000;
                public const string MaxLengthError = "Scope Description cannot exceed 1000 characters.";
            }
        }

        public static class SystemPermission
        {
            public static class Name
            {
                public const int MaxLength = 50;
                public const string MaxLengthError = "Name cannot exceed 50 characters.";
                public const string Pattern = "^[a-z0-9-]*$";
                public const string PatternInfo = "Use lowercase letters (a-z), digits (0-9), and hyphens.";
                public const string PatternError = "Only lowercase letters, digits, and hyphens are allowed.";
            }
            public static class Description
            {
                public const int MaxLength = 400;
                public const string MaxLengthError = "Description cannot exceed 400 characters.";
            }
        }

        public static class Secret
        {
            public static class Description
            {
                public const int MaxLength = 200;
                public const string MaxLengthError = "Secret Description must be between 1 and 200 characters long.";
            }
        }
    }
}
