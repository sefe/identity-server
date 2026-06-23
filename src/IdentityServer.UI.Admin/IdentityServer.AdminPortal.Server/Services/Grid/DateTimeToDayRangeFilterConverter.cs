// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Telerik.DataSource;

namespace IdentityServer.AdminPortal.Server.Services.Grid;

public class DateTimeToDayRangeFilterConverter : IGridRequestProcessor
{
    private readonly string _memberName;

    public DateTimeToDayRangeFilterConverter(string memberName)
    {
        _memberName = memberName;
    }

    public Task ProcessGridRequestAsync(DataSourceRequest request)
    {
        return ProcessFilterDescriptorListAsync(request.Filters);
    }

    internal async Task ProcessFilterDescriptorListAsync(IList<IFilterDescriptor> filters)
    {
        if (filters == null || filters.Count == 0)
        {
            return;
        }

        for (int index = filters.Count - 1; index >= 0; index--)
        {
            IFilterDescriptor? filterObj = filters[index];
            if (filterObj is CompositeFilterDescriptor cfd)
            {
                await ProcessFilterDescriptorListAsync(cfd.FilterDescriptors);

                // avoid nesting empty composite filters
                if (cfd.FilterDescriptors.Count == 1)
                {
                    filters.RemoveAt(index);
                    filters.Insert(index, cfd.FilterDescriptors[0]);
                }
            }
            else
            {
                var dateRangeCompositeFilter = ProcessDateFilterDescriptor(filterObj);
                if (dateRangeCompositeFilter != null)
                {
                    // replace the original filter with a new date range composite
                    filters.RemoveAt(index);
                    filters.Insert(index, dateRangeCompositeFilter);
                }
            }
        }
    }

    internal CompositeFilterDescriptor? ProcessDateFilterDescriptor(IFilterDescriptor fdObj)
    {
        if (fdObj is FilterDescriptor fd &&
            fd.Member == _memberName &&
            fd.Value != null)
        {
            return ConvertDateFilterToDateRangeComposite(fd);
        }
        return null;
    }

    internal static CompositeFilterDescriptor? ConvertDateFilterToDateRangeComposite(FilterDescriptor fd)
    {
        switch (fd.Operator)
        {
            case FilterOperator.IsEqualTo:
                // IsEqualTo (23.09.2025) -> GreaterThanOrEqualTo(23.09.2025 00:00:00) AND LessThan(24.09.2025 00:00:00)
                fd.Operator = FilterOperator.IsGreaterThanOrEqualTo;
                return new CompositeFilterDescriptor
                {
                    LogicalOperator = FilterCompositionLogicalOperator.And,
                    FilterDescriptors = {
                        fd,
                        new FilterDescriptor()
                        {
                            Member = fd.Member,
                            MemberType = typeof(DateTime),
                            Operator = FilterOperator.IsLessThan,
                            Value = ((DateTime)fd.Value).AddDays(1)
                        }
                    }
                };
            case FilterOperator.IsNotEqualTo:
                // IsNotEqualTo (23.09.2025) -> LessThan(23.09.2025 00:00:00) OR GreaterThanOrEqualTo(24.09.2025 00:00:00)
                fd.Operator = FilterOperator.IsLessThan;
                return new CompositeFilterDescriptor
                {
                    LogicalOperator = FilterCompositionLogicalOperator.Or,
                    FilterDescriptors =
                    {
                        fd,
                        new FilterDescriptor()
                        {
                            Member = fd.Member,
                            MemberType = typeof(DateTime),
                            Operator = FilterOperator.IsGreaterThanOrEqualTo,
                            Value = ((DateTime)fd.Value).AddDays(1)
                        }
                    }
                };
            default:
                return null;
        }
    }
}

