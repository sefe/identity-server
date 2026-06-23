// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.AdminPortal.Web.Services;

public class ConfirmationService : IConfirmationService
{
    public event Func<string, string, string, bool, Task>? OnShow;
    private TaskCompletionSource<bool>? _tcs;

    public Task<bool> ConfirmLeavingDirtyPageAsync()
    {
        return ConfirmAsync("Confirm navigation", "The entered information will be lost. Are you sure you want to leave?");
    }

    public Task<bool> ConfirmAsync(string title, string message, bool confirmCancel = true)
    {
        return ConfirmAsync(title, message, string.Empty, confirmCancel);
    }

    public async Task<bool> ConfirmAsync(string title, string message, string link, bool confirmCancel = true)
    {
        _tcs = new TaskCompletionSource<bool>();
        if (OnShow != null)
        {
            await OnShow.Invoke(title, message, link, confirmCancel);
        }

        return await _tcs.Task;
    }

    public void SetConfirmationResult(bool confirmed)
    {
        _tcs?.SetResult(confirmed);
    }
}
