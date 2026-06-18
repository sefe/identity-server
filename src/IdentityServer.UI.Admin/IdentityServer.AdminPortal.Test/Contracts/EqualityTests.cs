using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.DTO.Clients;

namespace IdentityServer.AdminPortal.Test.Contracts;

[TestFixture]
public class EqualityTests
{
    [Test]
    public void NameEqualityTest()
    {
        var source1 = new List<ClientDtoRead> { new() { ClientId = "1", ClientName = "1" }, new() { ClientId = "2", ClientName = "2" } };
        var source2 = new List<ClientDtoRead> { new() { ClientId = "2", ClientName = "2" }, new() { ClientId = "3", ClientName = "3" } };

        var comparer = FieldEqualityComparer.For<ClientDtoRead>(c => c.ClientName);

        var oneVsTwo = source1.Except(source2, comparer).ToList();
        var twoVsOne = source2.Except(source1, comparer).ToList();
        var oneVsOne = source1.Except(source1, comparer).ToList();
        var twoVsTwo = source2.Except(source2, comparer).ToList();

        using (Assert.EnterMultipleScope())
        {
            Assert.That(oneVsTwo.Single(c => c.ClientName == "1"), Is.Not.Null);
            Assert.That(twoVsOne.Single(c => c.ClientName == "3"), Is.Not.Null);
            Assert.That(oneVsOne, Is.Empty);
            Assert.That(twoVsTwo, Is.Empty);
        }
    }

    [Test]
    public void IdEqualityTest()
    {
        var source1 = new List<ClientDtoRead> { new() { Id = 1, ClientId = "1", ClientName = "1" }, new() { Id = 2, ClientId = "2", ClientName = "2" } };
        var source2 = new List<ClientDtoRead> { new() { Id = 2, ClientId = "2", ClientName = "2" }, new() { Id = 3, ClientId = "3", ClientName = "3" } };

        var comparer = IdEqualityComparer.For<ClientDtoRead, int>();

        var oneVsTwo = source1.Except(source2, comparer).ToList();
        var twoVsOne = source2.Except(source1, comparer).ToList();
        var oneVsOne = source1.Except(source1, comparer).ToList();
        var twoVsTwo = source2.Except(source2, comparer).ToList();

        using (Assert.EnterMultipleScope())
        {
            Assert.That(oneVsTwo.Single(c => c.Id == 1), Is.Not.Null);
            Assert.That(twoVsOne.Single(c => c.Id == 3), Is.Not.Null);
            Assert.That(oneVsOne, Is.Empty);
            Assert.That(twoVsTwo, Is.Empty);
        }
    }
}
