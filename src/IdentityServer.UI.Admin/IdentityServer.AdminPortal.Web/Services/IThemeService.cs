// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Telerik.SvgIcons;

namespace IdentityServer.AdminPortal.Web.Services;

/// <summary>
/// Service for managing application theme preferences and detection.
/// </summary>
public interface IThemeService
{
    /// <summary>
    /// Gets the current active theme mode.
    /// </summary>
    ThemeMode CurrentTheme { get; }

    /// <summary>
    /// Event raised when the theme changes.
    /// </summary>
    event EventHandler<ThemeMode>? OnThemeChanged;

    /// <summary>
    /// Initializes the theme service by detecting browser preference and loading user preference from storage.
    /// </summary>
    Task InitializeAsync();

    /// <summary>
    /// Sets the theme mode and persists the preference.
    /// </summary>
    /// <param name="mode">The theme mode to apply.</param>
    Task SetThemeAsync(ThemeMode mode);

    /// <summary>
    /// Gets the effective theme (resolves Auto to Light or Dark based on browser preference).
    /// </summary>
    /// <returns>The effective theme (Light or Dark).</returns>
    Task<EffectiveTheme> GetEffectiveThemeAsync();

    ISvgIcon GetInfoIcon();
}

/// <summary>
/// Represents the theme mode preference.
/// </summary>
public enum ThemeMode
{
    /// <summary>
    /// Automatically detect theme from browser preference.
    /// </summary>
    Auto = 0,

    /// <summary>
    /// Light theme.
    /// </summary>
    Light = 1,

    /// <summary>
    /// Dark theme.
    /// </summary>
    Dark = 2
}

/// <summary>
/// Represents the effective theme after resolving Auto mode.
/// </summary>
public enum EffectiveTheme
{
    /// <summary>
    /// Light theme.
    /// </summary>
    Light = 0,

    /// <summary>
    /// Dark theme.
    /// </summary>
    Dark = 1
}
