using System.Linq.Expressions;

namespace IdentityServer.Tests.Common.Builders;

public class MockStorageBuilder<T> where T : class
{
    protected readonly MockStorage<T> _mockStorage;

    public MockStorageBuilder(Expression<Func<T, int>> idExpression)
    {
        _mockStorage = new MockStorage<T>(idExpression);
    }

    public MockStorageBuilder<T> WithItem(T item)
    {
        _mockStorage.Items.Add(item);
        return this;
    }

    public MockStorage<T> Build()
    {
        return _mockStorage;
    }
}
