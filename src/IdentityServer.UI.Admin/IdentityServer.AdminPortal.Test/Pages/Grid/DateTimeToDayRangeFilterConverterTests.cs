// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Telerik.DataSource;
using IdentityServer.AdminPortal.Server.Services.Grid;

namespace IdentityServer.AdminPortal.Test.Pages.Grid;

[TestFixture]
public class DateTimeToDayRangeFilterConverterTests
{
    private const string _memberName = "TestDate";

    [Test]
    public void ProcessDateFilterDescriptor_OnNotMatchingMember_ReturnsNull()
    {
        // Arrange
        var filter = new FilterDescriptor
        {
            Member = "OtherMember",
            MemberType = typeof(DateTime),
            Operator = FilterOperator.IsEqualTo,
            Value = DateTime.UtcNow
        };
        var converter = new DateTimeToDayRangeFilterConverter(_memberName);

        // Act
        var result = converter.ProcessDateFilterDescriptor(filter);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public void ProcessDateFilterDescriptor_OnNullValue_ReturnsNull()
    {
        // Arrange
        var filter = new FilterDescriptor
        {
            Member = _memberName,
            MemberType = typeof(DateTime),
            Operator = FilterOperator.IsEqualTo,
            Value = null
        };
        var converter = new DateTimeToDayRangeFilterConverter(_memberName);

        // Act
        var result = converter.ProcessDateFilterDescriptor(filter);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public void ConvertDateFilterToDateRangeComposite_OnOtherOperator_ReturnsNull()
    {
        // Arrange
        var filter = new FilterDescriptor
        {
            Member = _memberName,
            MemberType = typeof(DateTime),
            Operator = FilterOperator.IsGreaterThan,
            Value = DateTime.UtcNow
        };

        // Act
        var result = DateTimeToDayRangeFilterConverter.ConvertDateFilterToDateRangeComposite(filter);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public async Task ProcessGridRequestAsync_OnNoMatchingFilter_DoesNothing()
    {
        // Arrange
        var filter = new FilterDescriptor
        {
            Member = "OtherMember",
            MemberType = typeof(DateTime),
            Operator = FilterOperator.IsEqualTo,
            Value = new DateTime(2024, 4, 1, 0, 0, 0, DateTimeKind.Utc),
        };
        var composite = new CompositeFilterDescriptor();
        composite.FilterDescriptors.Add(filter);
        var request = new DataSourceRequest() { Filters = new List<IFilterDescriptor>() { composite } };
        var converter = new DateTimeToDayRangeFilterConverter(_memberName);

        // Act
        await converter.ProcessGridRequestAsync(request);

        // Assert
        Assert.That(request.Filters, Has.Exactly(1).Items, "Should not add a new filter");
    }

    [Test]
    public async Task ProcessGridRequestAsync_OnNonCompositeFilter_ReplacesWithComposite()
    {
        // Arrange
        var filterDate = new DateTime(2024, 4, 6, 0, 0, 0, DateTimeKind.Utc);
        var filter = new FilterDescriptor
        {
            Member = _memberName,
            MemberType = typeof(DateTime),
            Operator = FilterOperator.IsEqualTo,
            Value = filterDate
        };
        var request = new DataSourceRequest() { Filters = new List<IFilterDescriptor>() { filter } };
        var converter = new DateTimeToDayRangeFilterConverter(_memberName);

        // Act
        await converter.ProcessGridRequestAsync(request);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(request.Filters, Has.Count.EqualTo(1));
            Assert.That(request.Filters[0], Is.TypeOf<CompositeFilterDescriptor>());
            var added = request.Filters[0] as CompositeFilterDescriptor;
            Assert.That(added.LogicalOperator, Is.EqualTo(FilterCompositionLogicalOperator.And));
            Assert.That(((FilterDescriptor)added.FilterDescriptors[0]).Value, Is.EqualTo(filterDate));
            Assert.That(((FilterDescriptor)added.FilterDescriptors[0]).Operator, Is.EqualTo(FilterOperator.IsGreaterThanOrEqualTo));
            Assert.That(((FilterDescriptor)added.FilterDescriptors[1]).Value, Is.EqualTo(filterDate.AddDays(1)));
            Assert.That(((FilterDescriptor)added.FilterDescriptors[1]).Operator, Is.EqualTo(FilterOperator.IsLessThan));
        }
    }

    [Test]
    public void ProcessDateFilterDescriptor_OnNotFilterDescriptor_ReturnsNull()
    {
        // Arrange
        var notAFilterDescriptor = new object();
        var converter = new DateTimeToDayRangeFilterConverter(_memberName);

        // Act
        var result = converter.ProcessDateFilterDescriptor(notAFilterDescriptor as IFilterDescriptor);

        // Assert
        Assert.That(result, Is.Null);
    }

    [Test]
    public void ConvertDateFilterToDateRangeComposite_OnNotEqualToOperator_ReturnsOrComposite()
    {
        // Arrange
        var date = new DateTime(2024, 5, 1, 0, 0, 0, DateTimeKind.Utc);
        var filter = new FilterDescriptor
        {
            Member = _memberName,
            MemberType = typeof(DateTime),
            Operator = FilterOperator.IsNotEqualTo,
            Value = date
        };

        // Act
        var result = DateTimeToDayRangeFilterConverter.ConvertDateFilterToDateRangeComposite(filter);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.LogicalOperator, Is.EqualTo(FilterCompositionLogicalOperator.Or));
            Assert.That(result.FilterDescriptors, Has.Count.EqualTo(2));
            var first = result.FilterDescriptors[0] as FilterDescriptor;
            var second = result.FilterDescriptors[1] as FilterDescriptor;
            Assert.That(first.Operator, Is.EqualTo(FilterOperator.IsLessThan));
            Assert.That(second.Operator, Is.EqualTo(FilterOperator.IsGreaterThanOrEqualTo));
            Assert.That(second.Value, Is.EqualTo(date.AddDays(1)));
        }
    }

    [Test]
    public void ConvertDateFilterToDateRangeComposite_OnNonDateTimeValue_ThrowsInvalidCastException()
    {
        // Arrange
        var filter = new FilterDescriptor
        {
            Member = _memberName,
            MemberType = typeof(DateTime),
            Operator = FilterOperator.IsEqualTo,
            Value = "not a date"
        };

        // Act & Assert
        Assert.Throws<InvalidCastException>(() =>
            DateTimeToDayRangeFilterConverter.ConvertDateFilterToDateRangeComposite(filter));
    }

    [Test]
    public async Task ProcessFilterDescriptorListAsync_OnSingleChildComposite_ReplacesWithChild()
    {
        // Arrange
        var filter = new FilterDescriptor
        {
            Member = _memberName,
            MemberType = typeof(DateTime),
            Operator = FilterOperator.IsGreaterThan,
            Value = DateTime.UtcNow
        };
        var composite = new CompositeFilterDescriptor();
        composite.FilterDescriptors.Add(filter);
        var filters = new List<IFilterDescriptor> { composite };
        var converter = new DateTimeToDayRangeFilterConverter(_memberName);

        // Act
        await converter.ProcessFilterDescriptorListAsync(filters);

        // Assert
        Assert.That(filters, Has.Count.EqualTo(1));
        Assert.That(filters[0], Is.EqualTo(filter));
    }

    [Test]
    public async Task ProcessFilterDescriptorListAsync_OnDeeplyNestedComposite_AllAreProcessed()
    {
        // Arrange
        var date = new DateTime(2024, 6, 1, 0, 0, 0, DateTimeKind.Utc);
        var filter = new FilterDescriptor
        {
            Member = _memberName,
            MemberType = typeof(DateTime),
            Operator = FilterOperator.IsEqualTo,
            Value = date
        };
        var innerComposite = new CompositeFilterDescriptor();
        innerComposite.FilterDescriptors.Add(filter);
        var outerComposite = new CompositeFilterDescriptor();
        outerComposite.FilterDescriptors.Add(innerComposite);
        var filters = new List<IFilterDescriptor> { outerComposite };
        var converter = new DateTimeToDayRangeFilterConverter(_memberName);

        // Act
        await converter.ProcessFilterDescriptorListAsync(filters);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(filters, Has.Count.EqualTo(1));
            Assert.That(filters[0], Is.TypeOf<CompositeFilterDescriptor>());
            var resultComposite = (CompositeFilterDescriptor)filters[0];
            Assert.That(resultComposite.FilterDescriptors, Has.Count.EqualTo(2));
            var added = resultComposite.FilterDescriptors[1] as FilterDescriptor;
            Assert.That(added.Operator, Is.EqualTo(FilterOperator.IsLessThan));
            Assert.That(added.Value, Is.EqualTo(date.AddDays(1)));
        }
    }

    [Test]
    public async Task ProcessFilterDescriptorListAsync_OnEmptyList_DoesNothing()
    {
        // Arrange
        var filters = new List<IFilterDescriptor>();
        var converter = new DateTimeToDayRangeFilterConverter(_memberName);

        // Act
        await converter.ProcessFilterDescriptorListAsync(filters);

        // Assert
        Assert.That(filters, Is.Empty);
    }
}
