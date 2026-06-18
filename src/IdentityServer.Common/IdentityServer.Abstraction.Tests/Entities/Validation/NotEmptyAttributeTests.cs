using System.Collections;
using System.ComponentModel.DataAnnotations;
using IdentityServer.Abstraction.Entities.Validation;

namespace IdentityServer.Abstraction.Tests.Entities.Validation;

[TestFixture]
public class NotEmptyAttributeTests
{
    private readonly NotEmptyAttribute _attribute = new();

    [TestCaseSource(nameof(SuccessfulValidationData))]
    public void IsValid_ReturnsTrue_ForValidInputs(object value)
    {
        var context = new ValidationContext(new object(), null, null) { MemberName = "afield" };
        Assert.That(_attribute.GetValidationResult(value, context), Is.EqualTo(ValidationResult.Success));
    }

    [TestCaseSource(nameof(FailingValidationData))]
    public void IsValid_ReturnsFalse_ForInvalidInputs(object value)
    {
        var context = new ValidationContext(new object(), null, null) { MemberName = "afield" };
        Assert.That(_attribute.GetValidationResult(value, context)?.ErrorMessage, Is.Not.Null);
    }

    private static IEnumerable<TestCaseData> SuccessfulValidationData()
    {
        yield return new TestCaseData(new List<int> { 1 });
        yield return new TestCaseData(new List<string> { "item" });
    }

    private static IEnumerable<TestCaseData> FailingValidationData()
    {
        yield return new TestCaseData(new List<int>());
        yield return new TestCaseData(Array.Empty<int>());
        yield return new TestCaseData(null);
        yield return new TestCaseData(123);
        yield return new TestCaseData(new ThrowingEnumerable());
    }

    public class ThrowingEnumerable : IEnumerable
    {
        public IEnumerator GetEnumerator() => new ThrowingEnumerator();

        private class ThrowingEnumerator : IEnumerator
        {
            public object Current => null!;

            public static void Dispose()
            {
                throw new NotImplementedException();
            }

            public bool MoveNext() => throw new InvalidOperationException("Test exception");
            public void Reset() => throw new NotSupportedException();
        }
    }
}
