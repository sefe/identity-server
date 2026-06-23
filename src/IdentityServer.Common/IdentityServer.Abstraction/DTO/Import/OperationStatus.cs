// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

namespace IdentityServer.Abstraction.DTO.Import;

public class OperationStatus
{
    public bool IsCompleted { get; set; } = false;
    public List<string> Errors { get; set; } = new();
    public List<string> Warnings { get; set; } = new();
    public bool HasErrors => Errors.Count > 0;

    override public string ToString()
    {
        return $"Errors: {string.Join(", ", Errors)}, Warnings: {string.Join(", ", Warnings)}";
    }
}

public class OperationStatus<T> : OperationStatus
{
    public required T Result { get; set; }
}
