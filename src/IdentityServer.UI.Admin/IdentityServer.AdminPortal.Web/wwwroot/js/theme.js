// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

(function() {
    'use strict';

    // Constants
    const STORAGE_KEY = 'theme';
    const THEME_DARK = 'dark';
    const THEME_LIGHT = 'light';
    const THEME_AUTO = 'auto';
    const TELERIK_THEME_ID = 'telerik-theme';
    const TELERIK_THEMES = {
        dark: 'css/telerik/bootstrap-main-dark.css',
        light: 'css/telerik/bootstrap-main.css'
    };

    // Cached media query
    const darkModeQuery = window.matchMedia('(prefers-color-scheme: dark)');

    // Helper functions
    const getStoredTheme = () => localStorage.getItem(STORAGE_KEY);

    const prefersDarkMode = () => darkModeQuery.matches;

    const getPreferredTheme = () => {
        const storedTheme = getStoredTheme();
        if (storedTheme === THEME_LIGHT || storedTheme === THEME_DARK) {
            return storedTheme;
        }
        return prefersDarkMode() ? THEME_DARK : THEME_LIGHT;
    };

    const resolveTheme = (theme) => {
        if (theme === THEME_AUTO || (theme !== THEME_LIGHT && theme !== THEME_DARK)) {
            return prefersDarkMode() ? THEME_DARK : THEME_LIGHT;
        }
        return theme;
    };

    const applyBootstrapTheme = (theme) => {
        document.documentElement.setAttribute('data-bs-theme', theme);
    };

    const applyTelerikTheme = (theme) => {
        const newThemeUrl = TELERIK_THEMES[theme] || TELERIK_THEMES.light;
        const existingLink = document.getElementById(TELERIK_THEME_ID);

        // Skip if already loaded
        if (existingLink?.getAttribute('href') === newThemeUrl) {
            return;
        }

        const newLink = document.createElement('link');
        newLink.id = TELERIK_THEME_ID;
        newLink.rel = 'stylesheet';
        newLink.href = newThemeUrl;

        // Replace existing link after new one loads
        if (existingLink) {
            newLink.onload = () => existingLink.remove();
        }

        newLink.onerror = () => {
            console.error(`Failed to load Telerik theme: ${newThemeUrl}`);
        };

        // Insert after bootstrap CSS link to ensure proper cascade order
        const bootstrapLink = document.getElementById('bootstrapcss');
        if (bootstrapLink && bootstrapLink.nextSibling) {
            bootstrapLink.parentNode.insertBefore(newLink, bootstrapLink.nextSibling);
        } else {
            document.head.appendChild(newLink);
        }
    };

    const setTheme = (theme) => {
        const resolvedTheme = resolveTheme(theme);
        applyBootstrapTheme(resolvedTheme);
        applyTelerikTheme(resolvedTheme);
    };

    // Apply initial theme on page load
    setTheme(getPreferredTheme());

    // Listen for system theme changes (only when no explicit preference is stored)
    darkModeQuery.addEventListener('change', () => {
        const storedTheme = getStoredTheme();
        if (storedTheme !== THEME_LIGHT && storedTheme !== THEME_DARK) {
            setTheme(getPreferredTheme());
        }
    });

    // Expose ThemeManager globally for module imports (used by Blazor ThemeService)
    window.ThemeManager = {
        prefersDarkMode,
        applyTelerikTheme,
        applyBootstrapTheme,
        applyTheme: setTheme
    };
})();
