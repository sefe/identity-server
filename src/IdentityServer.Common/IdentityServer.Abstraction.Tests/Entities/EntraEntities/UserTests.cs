using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.EntraEntities;

namespace IdentityServer.Abstraction.Tests.Entities.EntraEntities;

[TestFixture]
public class UserTests
{
    [Test]
    public void Id_GetterAndSetter_WorksCorrectly()
    {
        // Arrange
        var user = new User { OId = "user-1" };

        // Act
        var id = ((IHasId<string>)user).Id;
        ((IHasId<string>)user).Id = "user-2";
        var newId = ((IHasId<string>)user).Id;

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(id, Is.EqualTo("user-1"));
            Assert.That(newId, Is.EqualTo("user-2"));
            Assert.That(user.OId, Is.EqualTo("user-2"));
        }
    }

    [Test]
    public void Equals_SameOId_ReturnsTrue()
    {
        // Arrange
        var user1 = new User { OId = "abc123", DisplayName = "User1", AccountEnabled = true };
        var user2 = new User { OId = "abc123", DisplayName = "User2", AccountEnabled = false };

        // Act
        var result = user1.Equals(user2);

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void Equals_DifferentOId_ReturnsFalse()
    {
        // Arrange
        var user1 = new User { OId = "abc123" };
        var user2 = new User { OId = "def456" };

        // Act
        var result = user1.Equals(user2);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void Equals_Null_ReturnsFalse()
    {
        // Arrange
        var user1 = new User { OId = "abc123" };

        // Act
        var result = user1.Equals(null);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void Equals_SameReference_ReturnsTrue()
    {
        // Arrange
        var user1 = new User { OId = "abc123" };
        var user2 = user1;

        // Act
        var result = user1.Equals(user2);

        // Assert
        Assert.That(result, Is.True);
    }

    [Test]
    public void Equals_DifferentType_ReturnsFalse()
    {
        // Arrange
        var user1 = new User { OId = "abc123" };
        var notAUser = new object();

        // Act
        var result = user1.Equals(notAUser);

        // Assert
        Assert.That(result, Is.False);
    }

    [Test]
    public void GetHashCode_SameOId_SameHashCode()
    {
        // Arrange
        var user1 = new User { OId = "abc123" };
        var user2 = new User { OId = "abc123" };

        // Act
        var hash1 = user1.GetHashCode();
        var hash2 = user2.GetHashCode();

        // Assert
        Assert.That(hash1, Is.EqualTo(hash2));
    }

    [Test]
    public void GetHashCode_DifferentOId_DifferentHashCode()
    {
        // Arrange
        var user1 = new User { OId = "abc123" };
        var user2 = new User { OId = "def456" };

        // Act
        var hash1 = user1.GetHashCode();
        var hash2 = user2.GetHashCode();

        // Assert
        Assert.That(hash1, Is.Not.EqualTo(hash2));
    }

    [Test]
    public void GetHashCode_NullOId_ReturnsZero()
    {
        // Arrange
        var user = new User { OId = null! };

        // Act
        var hash = user.GetHashCode();

        // Assert
        Assert.That(hash, Is.Zero);
    }
}
