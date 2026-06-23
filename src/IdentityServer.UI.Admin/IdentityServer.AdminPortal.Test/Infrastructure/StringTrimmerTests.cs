// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Telerik.DataSource;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.AdminPortal.Server.Infrastructure;

namespace IdentityServer.AdminPortal.Test.Infrastructure;

public class StringTrimmerTests
{
    [Test]
    public void TrimAllStrings_OnComplexObject_TrimsAllNestedStrings()
    {
        // Arrange
        var dt = DateTime.UtcNow;
        var client = new ClientDtoRead()
        {
            ClientId = "   TestClient  ",
            ClientName = "   Test Client   ",
            SystemPermissionEnvironmentId = 1,
            AllowedCorsOrigins = new List<ClientPropertyCorsOriginDtoRead> { new() { Origin = "  http://example1.com  " }, new() { Origin = "  http://example2.com  " } },
            AllowedScopes = new List<ClientPropertyScopeDtoRead> { new() { Scope = "   scope1    " } },
            ClientSecrets = new List<ClientPropertySecretDtoRead> { new() { Description = " \tdesc " } },
            Description = "  Test Client Description  ",
            RedirectUris = new List<ClientPropertyRedirectUriDtoRead> { new() { RedirectUri = "  http://localhost:5000/callback \r\n " } },
            Roles = new List<ClientPropertyRoleDtoRead>
            {
                new() {
                    RoleName = "   role1    ",
                    Mappings = new List<ClientPropertyRoleMappingDtoRead>()
                    {
                        new()
                        {
                            Description = "  Test Role Description  ",
                            Value =    "  Test Role Value  ",
                        }
                    }
                }
            },
            Created = dt.AddDays(-1),
            Updated = dt,
            Enabled = true,
            AccessTokenType = Abstraction.Entities.IdentityServerConfig.ClientAccessTokenType.Reference
        };

        // Act
        StringTrimmer.TrimAllStrings(client);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(client.ClientId, Is.EqualTo("TestClient"));
            Assert.That(client.ClientName, Is.EqualTo("Test Client"));
            Assert.That(client.Description, Is.EqualTo("Test Client Description"));

            Assert.That(client.AllowedCorsOrigins[0].Origin, Is.EqualTo("http://example1.com"));
            Assert.That(client.AllowedCorsOrigins[1].Origin, Is.EqualTo("http://example2.com"));
            Assert.That(client.AllowedScopes[0].Scope, Is.EqualTo("scope1"));
            Assert.That(client.ClientSecrets[0].Description, Is.EqualTo("desc"));
            Assert.That(client.RedirectUris[0].RedirectUri, Is.EqualTo("http://localhost:5000/callback"));

            Assert.That(client.Roles[0].RoleName, Is.EqualTo("role1"));
            Assert.That(client.Roles[0].Mappings[0].Description, Is.EqualTo("Test Role Description"));
            Assert.That(client.Roles[0].Mappings[0].Value, Is.EqualTo("Test Role Value"));

            Assert.That(client.Created, Is.EqualTo(dt.AddDays(-1)));
            Assert.That(client.Updated, Is.EqualTo(dt));
            Assert.That(client.AccessTokenType, Is.EqualTo(Abstraction.Entities.IdentityServerConfig.ClientAccessTokenType.Reference));
            Assert.That(client.Enabled, Is.True);
        }
    }

    [Test]
    public void TrimAllStrings_OnListOfObjects_TrimsAllNestedStrings()
    {
        // Arrange
        var allowedCorsOrigins = new List<ClientPropertyCorsOriginDtoRead> { new() { Origin = "  http://example1.com  " }, new() { Origin = "  http://example2.com  " } };

        // Act
        StringTrimmer.TrimAllStrings(allowedCorsOrigins);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(allowedCorsOrigins[0].Origin, Is.EqualTo("http://example1.com"));
            Assert.That(allowedCorsOrigins[1].Origin, Is.EqualTo("http://example2.com"));
        }
    }

    [Test]
    public void TrimAllStrings_OnListOfStrings_TrimsValues()
    {
        // Arrange
        var values = new List<string> { " 1 ", "   \t 123 \t ", null, "", "    \t   " };

        // Act
        StringTrimmer.TrimAllStrings(values);

        // Assert
        Assert.That(values, Is.EquivalentTo(new List<string> { "1", "123", null, "", "" }));
    }

    [Test]
    public void TrimAllStrings_OnArrayOfStrings_TrimsValues()
    {
        // Arrange
        var values = new string[] { " 1 ", "   \t 123 \t ", null, "", "    \t   " };

        // Act
        StringTrimmer.TrimAllStrings(values);

        // Assert
        Assert.That(values, Is.EquivalentTo(new string[] { "1", "123", null, "", "" }));
    }

    [Test]
    public void TrimAllStrings_OnDictionaryOfStrings_TrimsValues()
    {
        // Arrange
        var values = new Dictionary<string, string>() { { " 1 ", " 1 " }, { " 2 ", "  \t 123 \t " }, { " 3 ", null }, { "4", "" }, { "5", "    \t   " } };

        // Act
        StringTrimmer.TrimAllStrings(values);

        // Assert
        Assert.That(values, Is.EquivalentTo(new Dictionary<string, string>() { { " 1 ", "1" }, { " 2 ", "123" }, { " 3 ", null }, { "4", "" }, { "5", "" } }));
    }

    [Test]
    public void TrimAllStrings_OnDictionaryOfObjects_ProcessesObjects()
    {
        // Arrange
        var values = new Dictionary<string, A>() { { " 1 ", new A(" 1 ") }, { " 2 ", new A("  \t 123 \t ") }, { " 3 ", new A(null) },
            { "4", new A("") }, { "5", new A("    \t   ") } };

        // Act
        StringTrimmer.TrimAllStrings(values);

        // Assert
        Assert.That(values, Is.EquivalentTo(new Dictionary<string, A>() { { " 1 ", new A("1") }, { " 2 ", new A("123") }, { " 3 ", new A(null) },
            { "4", new A("") }, { "5", new A("") } }));
    }

    [Test]
    public void TrimAllStrings_DataSourceRequest_Filters()
    {
        // Arrange
        var request = new DataSourceRequest
        {
            Filters = new List<IFilterDescriptor> {
                new FilterDescriptor { Member = "propName", Operator = FilterOperator.IsEqualTo, Value = " value "}
            }
        };

        // Act
        StringTrimmer.TrimAllStrings(request);

        // Assert
        Assert.That(((FilterDescriptor)request.Filters[0]).Value, Is.EqualTo("value"));
    }

    [Test]
    public void TrimAllStrings_OnObjectWithCollections_ProcessesCollections()
    {
        // Arrange
        var a = new ComplexObject()
        {
            ListOfString = new List<string> { "  \t  Item1  \t ", "  Item2  ", null, "   " },
            DictOfA = new Dictionary<string, A>
            {
                { "Key1", new A("  Value1  ") },
                { "Key2", new A("  \t Value2 \t ") },
                { "Key3", new A(null) },
                { "Key4", new A("") },
                { "Key5", new A("    \t   ") }
            },
            DictOfString = new Dictionary<string, string>()
            {
                { " 1 ", " 1 " },
                { " 2 ", "  \t 123 \t " },
                { " 3 ", null },
                { "4", "" },
                {"5", "    \t   " }
            }
        };

        // Act
        StringTrimmer.TrimAllStrings(a);

        // Assert
        using (Assert.EnterMultipleScope())
        {
            Assert.That(a.ListOfString, Is.EquivalentTo(new List<string> { "Item1", "Item2", null, "" }));
            Assert.That(a.DictOfA, Is.EquivalentTo(new Dictionary<string, A>() { { "Key1", new A("Value1") }, { "Key2", new A("Value2") }, { "Key3", new A(null) },
                { "Key4", new A("") }, { "Key5", new A("") } }));
            Assert.That(a.DictOfString, Is.EquivalentTo(new Dictionary<string, string>() { { " 1 ", "1" }, { " 2 ", "123" }, { " 3 ", null }, { "4", "" }, { "5", "" } }));
        }
    }

    internal class A
    {
        public string B { get; set; }
        public A(string b)
        {
            B = b;
        }

        public override bool Equals(object obj)
        {
            if (obj is A a)
            {
                return B == a.B;
            }
            return false;
        }

        public override int GetHashCode()
        {
            return B == null ? 0 : B.GetHashCode();
        }
    }

    internal class ComplexObject
    {
        public List<string> ListOfString { get; set; }
        public Dictionary<string, A> DictOfA { get; set; }
        public Dictionary<string, string> DictOfString { get; set; }

    }
}
