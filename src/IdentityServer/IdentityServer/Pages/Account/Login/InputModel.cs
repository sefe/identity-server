// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.ComponentModel.DataAnnotations;

namespace IdentityServer.Pages.Account.Login;

public class InputModel
{
    [Required]
    public string? Username { get; set; }
    [Required]
    public string? Password { get; set; }
    public bool RememberLogin { get; set; }
    public string? ReturnUrl { get; set; }
    public string? Button { get; set; }
}
