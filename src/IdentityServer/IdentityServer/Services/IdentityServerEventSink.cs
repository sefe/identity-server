// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.Events;
using Duende.IdentityServer.Services;
using static IdentityServer.Abstraction.Constants;

namespace IdentityServer.Services;

public class IdentityServerEventSink : IEventSink
{
    private readonly ILogger<IdentityServerEventSink> _logger;
    private readonly IHttpContextAccessor _httpContextAccessor;

    public IdentityServerEventSink(ILogger<IdentityServerEventSink> logger, IHttpContextAccessor httpContextAccessor)
    {
        _logger = logger;
        _httpContextAccessor = httpContextAccessor;
    }
    public Task PersistAsync(Event evt)
    {
        _logger.LogInformation("IdentityServer Event: {@Event}", evt);

        EnrichContextFromEvent(evt);

        return Task.CompletedTask;
    }

    private void EnrichContextFromEvent(Event evt)
    {
        var context = _httpContextAccessor.HttpContext;
        if (context == null)
        {
            return;
        }

        EnrichFromEvent(context, evt);
    }

    private static void EnrichFromEvent(HttpContext context, Event evt)
    {
        switch (evt)
        {
            case BackchannelAuthenticationFailureEvent backchannelAuthFailureEvent:
                EnrichFromEvent(context, backchannelAuthFailureEvent);
                break;

            case BackchannelAuthenticationSuccessEvent backchannelAuthSuccessEvent:
                EnrichFromEvent(context, backchannelAuthSuccessEvent);
                break;

            case ClientAuthenticationFailureEvent clientAuthFailureEvent:
                EnrichFromEvent(context, clientAuthFailureEvent);
                break;

            case ClientAuthenticationSuccessEvent clientAuthSuccessEvent:
                EnrichFromEvent(context, clientAuthSuccessEvent);
                break;

            case ConsentDeniedEvent consentDeniedEvent:
                EnrichFromEvent(context, consentDeniedEvent);
                break;

            case ConsentGrantedEvent consentGrantedEvent:
                EnrichFromEvent(context, consentGrantedEvent);
                break;

            case DeviceAuthorizationFailureEvent deviceAuthFailureEvent:
                EnrichFromEvent(context, deviceAuthFailureEvent);
                break;

            case DeviceAuthorizationSuccessEvent deviceAuthSuccessEvent:
                EnrichFromEvent(context, deviceAuthSuccessEvent);
                break;

            case GrantsRevokedEvent grantsRevokedEvent:
                EnrichFromEvent(context, grantsRevokedEvent);
                break;

            case InvalidClientConfigurationEvent invalidClientConfigEvent:
                EnrichFromEvent(context, invalidClientConfigEvent);
                break;

            case TokenIssuedSuccessEvent tokenIssuedSuccessEvent:
                EnrichFromEvent(context, tokenIssuedSuccessEvent);
                break;

            case TokenRevokedSuccessEvent tokenRevokedSuccessEvent:
                EnrichFromEvent(context, tokenRevokedSuccessEvent);
                break;

            case UserLoginFailureEvent userLoginFailureEvent:
                EnrichFromEvent(context, userLoginFailureEvent);
                break;

            case UserLoginSuccessEvent userLoginSuccessEvent:
                EnrichFromEvent(context, userLoginSuccessEvent);
                break;

            case UserLogoutSuccessEvent userLogoutSuccessEvent:
                EnrichFromEvent(context, userLogoutSuccessEvent);
                break;
        }
    }

    private static void EnrichFromEvent(HttpContext context, BackchannelAuthenticationFailureEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
        AddContextItem(context, CustomContextFields.SubjectId, evt.SubjectId);
    }

    private static void EnrichFromEvent(HttpContext context, BackchannelAuthenticationSuccessEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
        AddContextItem(context, CustomContextFields.SubjectId, evt.SubjectId);
    }

    private static void EnrichFromEvent(HttpContext context, ClientAuthenticationFailureEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
    }

    private static void EnrichFromEvent(HttpContext context, ClientAuthenticationSuccessEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
        AddContextItem(context, CustomContextFields.AuthMethod, evt.AuthenticationMethod);
    }

    private static void EnrichFromEvent(HttpContext context, ConsentDeniedEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
        AddContextItem(context, CustomContextFields.SubjectId, evt.SubjectId);
    }

    private static void EnrichFromEvent(HttpContext context, ConsentGrantedEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
        AddContextItem(context, CustomContextFields.SubjectId, evt.SubjectId);
    }

    private static void EnrichFromEvent(HttpContext context, DeviceAuthorizationFailureEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
    }

    private static void EnrichFromEvent(HttpContext context, DeviceAuthorizationSuccessEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
    }

    private static void EnrichFromEvent(HttpContext context, GrantsRevokedEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
        AddContextItem(context, CustomContextFields.SubjectId, evt.SubjectId);
    }

    private static void EnrichFromEvent(HttpContext context, InvalidClientConfigurationEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
    }

    private static void EnrichFromEvent(HttpContext context, TokenIssuedSuccessEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
        AddContextItem(context, CustomContextFields.SubjectId, evt.SubjectId);
        AddContextItem(context, CustomContextFields.GrantType, evt.GrantType);
    }

    private static void EnrichFromEvent(HttpContext context, TokenRevokedSuccessEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
    }

    private static void EnrichFromEvent(HttpContext context, UserLoginFailureEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
    }

    private static void EnrichFromEvent(HttpContext context, UserLoginSuccessEvent evt)
    {
        AddContextItem(context, CustomContextFields.ClientId, evt.ClientId);
        AddContextItem(context, CustomContextFields.SubjectId, evt.SubjectId);
        AddContextItem(context, CustomContextFields.Username, evt.DisplayName);
    }

    private static void EnrichFromEvent(HttpContext context, UserLogoutSuccessEvent evt)
    {
        AddContextItem(context, CustomContextFields.SubjectId, evt.SubjectId);
    }

    private static void AddContextItem(HttpContext context, string key, string value)
    {
        if (!context.Items.ContainsKey(key) && !string.IsNullOrEmpty(value))
        {
            context.Items[key] = value;
        }
    }
}
