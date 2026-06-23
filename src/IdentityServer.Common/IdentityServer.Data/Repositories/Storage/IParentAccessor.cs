// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Data.Repositories.Storage;

public interface IParentAccessor<in TModel, in TParent>
{
    int GetParentEnvironmentId(TParent parent);
    int GetParentId(TModel model);
}
