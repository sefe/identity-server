// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Telerik.Blazor.Components;
using IdentityServer.AdminPortal.Web.Constants;

namespace IdentityServer.AdminPortal.Web.Models;

/// <summary>
/// Clone of <see cref="FileSelectFileInfo"/> but reads the whole file content into the memory
/// </summary>
public class FileSelectFileInfoWrapper : IDisposable
{
    private bool _disposed;

    public static FileSelectFileInfoWrapper Empty => new() { Name = "N/A", Stream = new MemoryStream() };

    public required string Name { get; set; }

    public required Stream Stream { get; set; }

    public static async Task<FileSelectFileInfoWrapper> Create(FileSelectFileInfo info)
    {
        var wrapper = new FileSelectFileInfoWrapper
        {
            Name = info.Name,
            Stream = await CopyDataStream(info),
        };

        return wrapper;
    }

    private static async Task<MemoryStream> CopyDataStream(FileSelectFileInfo info)
    {
        ArgumentNullException.ThrowIfNull(info);

        if (info.Stream is null)
        {
            return new MemoryStream();
        }

        MemoryStream memStream;
        if (info.Size > ImportRestrictions.MaxFileSize)
        {
            // Reject very large files as allocating a lot of memory is unsafe.
            throw new InvalidOperationException($"File size {info.Size} is too large.");
        }
        else if (info.Size > 0)
        {
            memStream = new MemoryStream((int)info.Size);
        }
        else
        {
            memStream = new MemoryStream();
        }

        // Copy data and reset position for consumers.
        await info.Stream.CopyToAsync(memStream);
        memStream.Seek(0, SeekOrigin.Begin);

        return memStream;
    }

    protected virtual void Dispose(bool disposing)
    {
        if (!_disposed)
        {
            if (disposing)
            {
                Stream?.Dispose();
            }
            _disposed = true;
        }
    }

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }
}
