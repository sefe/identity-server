// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Microsoft.AspNetCore.Components;
using Telerik.Blazor.Components;
using Telerik.DataSource;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.AdminPortal.Web.Extensions;
using IdentityServer.AdminPortal.Web.Models;
using IdentityServer.AdminPortal.Web.Services;
using IdentityServer.AdminPortal.Web.Services.Storage;

namespace IdentityServer.AdminPortal.Web.Pages.Grid;

/// <summary>
/// Wrapper class to store both GridState and PageSize together for caching
/// </summary>
/// <typeparam name="TDtoRead">The type of the grid data</typeparam>
public class GridStateWithPageSize<TDtoRead>
{
    public GridState<TDtoRead>? GridState { get; set; }
    public int PageSize { get; set; } = 20;
}

public abstract class GridListBasePage<TDtoRead> : UserRoleBasePage
{
    protected abstract string GridUniqueStorageKey { get; }
    protected TelerikGrid<TDtoRead> GridRef { get; set; } = default!;
    protected int PageSize { get; set; } = 20;
    protected List<int?> PageSizes { get; set; } = new List<int?> { 10, 20, 50 };
    protected List<FilterListOperator> ContainsOrNotLimitedFilterOperators = new() {
        new FilterListOperator { Operator = FilterOperator.Contains, Text = "Contains" },
        new FilterListOperator { Operator = FilterOperator.DoesNotContain, Text = "Does Not Contain" }
    };
    protected bool IsFirstLoad = true;
    protected bool ShowOnlyMyItems => _showOnlyMyItems;
    private bool _showOnlyMyItems; // backing field for toggle state
    protected bool ShowMyItemsToggleVisible => !HasAdmin;
    private const string _accessLevelFieldName = "AccessLevel";
    private GridStateWithPageSize<TDtoRead>? _cachedStateWithPageSize;
    private bool _stateLoaded;
    private bool _stateInitialized;

    [Inject]
    public IJSStorageService StorageService { get; set; } = default!;

    protected override async Task OnInitializedAsync()
    {
        await base.OnInitializedAsync();
        await LoadCachedState();
    }

    protected async Task ReadItems(GridReadEventArgs args)
    {
        // Wait for state initialization to complete before loading data
        if (!_stateInitialized)
        {
            return;
        }

        try
        {
            // we pass the request to the service, and there Telerik DataSource Extension methods will shape the data
            // then the service returns our project-specific envelope so that the data can be serialized by the framework
            ApiCallResult<DataEnvelope<TDtoRead>> response = await GetData(args.Request);
            if (!response.IsSuccess || response.Result == null)
            {
                ErrorMessage = response.ErrorMessage ?? "Unknown error occurred.";
                return;
            }
            else
            {
                ErrorMessage = null;
            }

            if (args.Request.Groups.Count > 0)
            {
                var data = GroupDataHelpers.DeserializeGroups<TDtoRead>(response.Result.GroupedData);
                args.Data = data.ToList();
            }
            else
            {
                args.Data = response.Result.CurrentPageData.ToList();
            }

            args.Total = response.Result.TotalItemCount;
        }
        finally
        {
            IsFirstLoad = false;
        }
    }

    protected abstract Task<ApiCallResult<DataEnvelope<TDtoRead>>> GetData(DataSourceRequest request);

    protected async Task OnStateInitHandler(GridStateEventArgs<TDtoRead> args)
    {
        if (!_stateLoaded)
        {
            await LoadCachedState();
        }

        if (_cachedStateWithPageSize?.GridState != null)
        {
            var gridState = _cachedStateWithPageSize.GridState;
            // Admin: ensure not constrained by cached AccessLevel filter, persist if removed
            if (HasAdmin && HasMyItemsFilter(gridState) && RemoveAccessLevelFilter(gridState))
            {
                gridState.Page = 1; // reset page since there was a change in filters
                await SaveGridState(gridState);
            }
            args.GridState = gridState;
        }

        _stateInitialized = true;
    }

    private async Task LoadCachedState()
    {
        try
        {
            _cachedStateWithPageSize = await StorageService.GetItem<GridStateWithPageSize<TDtoRead>>(GridUniqueStorageKey);
            if (_cachedStateWithPageSize != null)
            {
                PageSize = _cachedStateWithPageSize.PageSize;
                if (_cachedStateWithPageSize.GridState != null)
                {
                    _showOnlyMyItems = !HasAdmin && HasMyItemsFilter(_cachedStateWithPageSize.GridState);
                }
            }
            _stateLoaded = true;
        }
        catch (InvalidOperationException)
        {
            // JS Interop not available during pre-rendering
        }
    }

    protected Task OnStateChangedHandler(GridStateEventArgs<TDtoRead> args)
    {
        return SaveGridState(args.GridState);
    }

    protected async Task SaveGridState(GridState<TDtoRead> gridState)
    {
        if (RemoveFilterForInvisibleColumns(gridState))
        {
            await GridRef.SetStateAsync(gridState); // does NOT trigger GridStateChangedHandler recursively
        }

        // Save both GridState and current PageSize together
        var stateWithPageSize = new GridStateWithPageSize<TDtoRead>
        {
            GridState = gridState,
            PageSize = PageSize
        };
        await StorageService.SetItem(GridUniqueStorageKey, stateWithPageSize);
    }

    private static bool RemoveFilterForInvisibleColumns(GridState<TDtoRead> gridState)
    {
        var hiddenColumns = gridState.ColumnStates
            .Where(cs => cs.Visible == false)
            .Select(cs => cs.Field)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        if (hiddenColumns.Count == 0)
        {
            return false;
        }

        bool hasChanges = false;

        // Remove filters for hidden columns in composite filters
        foreach (var filterDescriptors in gridState.FilterDescriptors.OfType<CompositeFilterDescriptor>().Select(filter => filter.FilterDescriptors))
        {
            int removed = 0;
            for (int i = filterDescriptors.Count - 1; i >= 0; i--)
            {
                if (IsFilterDescriptorForHiddenColumn(filterDescriptors[i], hiddenColumns))
                {
                    filterDescriptors.RemoveAt(i);
                    removed++;
                }
            }

            if (removed > 0)
            {
                hasChanges = true;
            }
        }

        // Remove empty composite filters and simple filters for hidden columns
        var toRemove = gridState.FilterDescriptors
            .Where(fd =>
                (fd is CompositeFilterDescriptor cfd && cfd.FilterDescriptors.Count == 0) ||
                IsFilterDescriptorForHiddenColumn(fd, hiddenColumns)
            )
            .ToList();

        hasChanges |= toRemove.Count > 0;

        foreach (var fd in toRemove)
        {
            gridState.FilterDescriptors.Remove(fd);
        }

        return hasChanges;
    }

    private static bool IsFilterDescriptorForHiddenColumn(IFilterDescriptor fdObj, HashSet<string> hiddenColumns)
    {
        return fdObj is FilterDescriptor fd && fd.Value != null && hiddenColumns.Contains(fd.Member);
    }

    protected async Task ResetFilters()
    {
        var state = GridRef.GetState();

        state.FilterDescriptors.Clear();
        state.SearchFilter = null;

        _showOnlyMyItems = false;

        await GridRef.SetStateAsync(state);
        await SaveGridState(state);
    }

    protected async Task ResetState()
    {
        // clean up the storage
        await StorageService.RemoveItem(GridUniqueStorageKey);

        // Reset PageSize to default value
        PageSize = 20;

        await GridRef.SetStateAsync(null); // pass null to reset the state
    }

    /// <summary>
    /// Handler for PageSize changes to ensure PageSize is cached when changed
    /// </summary>
    protected async Task OnPageSizeChanged(int newPageSize)
    {
        GridRef.CurrentPage = 1; // reset to first page when page size changes
        PageSize = newPageSize;

        // Save the updated PageSize along with current grid state
        var currentState = GridRef.GetState();
        var stateWithPageSize = new GridStateWithPageSize<TDtoRead>
        {
            GridState = currentState,
            PageSize = PageSize
        };
        await StorageService.SetItem(GridUniqueStorageKey, stateWithPageSize);
    }

    /// <summary>
    /// Called from Razor pages when the user changes the "Show only My Items" toggle.
    /// Applies or removes the AccessLevel filter and persists state.
    /// </summary>
    protected async Task OnShowMyItemsChanged(bool newValue)
    {
        if (newValue == _showOnlyMyItems)
        {
            return; // no change
        }

        _showOnlyMyItems = newValue;
        await ApplyAccessFilterAsync(addMyItemsFilter: newValue);
    }

    private async Task ApplyAccessFilterAsync(bool addMyItemsFilter)
    {
        var state = GridRef.GetState() ?? new GridState<TDtoRead>();

        state.Page = 1;
        if (addMyItemsFilter)
        {
            // Add AccessLevel != None when MyItems is selected
            state.FilterDescriptors.Add(new FilterDescriptor
            {
                Member = _accessLevelFieldName,
                Operator = FilterOperator.IsNotEqualTo,
                Value = SystemPermissionRoleType.None
            });
        }
        else
        {
            RemoveAccessLevelFilter(state);
        }

        await GridRef.SetStateAsync(state);
        await SaveGridState(state);
    }

    private static bool HasMyItemsFilter(GridState<TDtoRead> state)
    {
        return state.FilterDescriptors.OfType<FilterDescriptor>()
            .Any(fd => string.Equals(fd.Member, _accessLevelFieldName, StringComparison.Ordinal) && fd.Operator == FilterOperator.IsNotEqualTo);
    }

    private static bool RemoveAccessLevelFilter(GridState<TDtoRead> state)
    {
        var filterToRemove = state.FilterDescriptors
            .OfType<FilterDescriptor>()
            .FirstOrDefault(fd => string.Equals(fd.Member, _accessLevelFieldName, StringComparison.Ordinal));
        if (filterToRemove == null)
        {
            return false;
        }

        state.FilterDescriptors.Remove(filterToRemove);
        return true;
    }
}
