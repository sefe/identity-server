// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Telerik.DataSource;
using IdentityServer.Abstraction.DTO.Clients;
using IdentityServer.Abstraction.Entities;

namespace IdentityServer.AdminPortal.Web.Services.Search;

public class ClientProvider : AdminApiProviderBase, ISearchProvider<ClientShortDtoRead>
{
    public ClientProvider(IAdminApiService adminApi) : base(adminApi)
    {
    }

    public async Task<SearchResult2<ClientShortDtoRead>> SearchAsync(string input, string? skipToken)
    {
        if (string.IsNullOrEmpty(skipToken) || !int.TryParse(skipToken, out int pageNumber))
        {
            pageNumber = 1;
        }

        var req = new DataSourceRequest
        {
            Page = pageNumber,
            PageSize = 10,
            Filters = new List<IFilterDescriptor>
            {
                new CompositeFilterDescriptor
                {
                    LogicalOperator = FilterCompositionLogicalOperator.Or,
                    FilterDescriptors = new FilterDescriptorCollection() {
                        new FilterDescriptor(nameof(ClientShortDtoRead.ClientId), FilterOperator.Contains, input),
                        new FilterDescriptor(nameof(ClientShortDtoRead.ClientName), FilterOperator.Contains, input),
                    }
                }
            }
        };

        var callResult = await AdminApi.GetClientsPaged(req);
        return new SearchResult2<ClientShortDtoRead>
        {
            Page = callResult.Result?.CurrentPageData,
            SkipToken = (pageNumber + 1).ToString(),
            ErrorMessage = callResult.ErrorMessage
        };
    }
}
