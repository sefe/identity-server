using Microsoft.JSInterop;
using Telerik.SvgIcons;
using IdentityServer.AdminPortal.Web.Services.Storage;

namespace IdentityServer.AdminPortal.Web.Services;

public class ThemeService : IThemeService
{
    private const string _storageKey = "theme";

    private readonly IJSRuntime _jsRuntime;
    private readonly IJSStorageService _localStorage;
    private bool _initialized;
    private bool _prefersDark;

    public ThemeMode CurrentTheme { get; private set; } = ThemeMode.Auto;

    public event EventHandler<ThemeMode>? OnThemeChanged;

    public ThemeService(IJSRuntime jsRuntime, IJSStorageService localStorage)
    {
        _jsRuntime = jsRuntime;
        _localStorage = localStorage;
    }

    public async Task InitializeAsync()
    {
        if (_initialized)
        {
            return;
        }

        try
        {
            var savedTheme = await _localStorage.GetString(_storageKey);
            CurrentTheme = Enum.TryParse<ThemeMode>(savedTheme, true, out var mode) ? mode : ThemeMode.Auto;

            _initialized = true;
        }
        catch (InvalidOperationException)
        {
            // Pre-rendering scenario - skip JS interop
        }
        catch (JSException)
        {
            // JavaScript error - skip JS interop
        }
    }

    public async Task SetThemeAsync(ThemeMode mode)
    {
        if (CurrentTheme == mode)
        {
            return;
        }

        CurrentTheme = mode;

        // Save to localStorage
        try
        {
            var jsCompatibleName = mode.ToString().ToLowerInvariant();
            await _localStorage.SetString(_storageKey, jsCompatibleName);
        }
        catch (InvalidOperationException)
        {
            // Pre-rendering scenario - ignore
        }

        // Apply the effective theme
        await ApplyEffectiveThemeAsync();

        // Notify listeners
        OnThemeChanged?.Invoke(this, mode);
    }

    public async Task<EffectiveTheme> GetEffectiveThemeAsync()
    {
        if (CurrentTheme == ThemeMode.Dark)
        {
            return EffectiveTheme.Dark;
        }

        if (CurrentTheme == ThemeMode.Light)
        {
            return EffectiveTheme.Light;
        }

        // Auto mode - detect browser preference
        try
        {
            _prefersDark = await _jsRuntime.InvokeAsync<bool>("ThemeManager.prefersDarkMode");
            return _prefersDark ? EffectiveTheme.Dark : EffectiveTheme.Light;
        }
        catch (InvalidOperationException)
        {
            // Pre-rendering fallback
            return EffectiveTheme.Light;
        }
        catch (JSException)
        {
            // JavaScript error - fallback to light
            return EffectiveTheme.Light;
        }
    }

    private async Task ApplyEffectiveThemeAsync()
    {
        var effectiveTheme = await GetEffectiveThemeAsync();
        var themeString = effectiveTheme.ToString().ToLowerInvariant();

        try
        {
            await _jsRuntime.InvokeVoidAsync("ThemeManager.applyTheme", themeString);
        }
        catch (InvalidOperationException)
        {
            // Pre-rendering scenario - ignore
        }
        catch (JSException)
        {
            // JavaScript error - ignore
        }
    }

    public ISvgIcon GetInfoIcon()
    {
        return CurrentTheme switch
        {
            ThemeMode.Dark => SvgIcon.InfoSolid,
            ThemeMode.Auto when _prefersDark => SvgIcon.InfoSolid,
            _ => SvgIcon.InfoCircle
        };
    }
}
