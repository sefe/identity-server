namespace IdentityServer.Abstraction.DTO.Export;

public class ExportResult
{
    public required string FileName { get; set; }
    public required object Result { get; set; }
}
