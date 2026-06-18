using System.Diagnostics.CodeAnalysis;
using AutoMapper;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Data.DuendeEntityExtensions;

namespace IdentityServer.Data.Configuration.Mappings;

[ExcludeFromCodeCoverage]
public class IdentityServerApiConfigurationMapProfile : Profile
{
    public IdentityServerApiConfigurationMapProfile()
    {
        CreateMap<ClientExt, ClientDtoSearchResponse>();
    }
}
