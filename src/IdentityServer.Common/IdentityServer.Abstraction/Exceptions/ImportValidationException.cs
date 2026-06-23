// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using IdentityServer.Abstraction.DTO.Import;

namespace IdentityServer.Abstraction.Exceptions;

public class ImportValidationException : Exception
{
    public ImportValidationException() { }

    public ImportValidationException(string message, OperationStatus validationSummary) : base(message)
    {
        ValidationSummary = validationSummary;
    }

    public ImportValidationException(string message, Exception inner) : base(message, inner) { }

    public OperationStatus ValidationSummary { get; } = new();
}
