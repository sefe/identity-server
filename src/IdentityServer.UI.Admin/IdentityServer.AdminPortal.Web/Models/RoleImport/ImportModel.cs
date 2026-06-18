using IdentityServer.Abstraction.DTO;
using IdentityServer.Abstraction.DTO.Import;

namespace IdentityServer.AdminPortal.Web.Models.RoleImport;

public abstract class ImportModel<TParsingResult> where TParsingResult : IDtoImport
{
    public OperationStatus<FileSelectFileInfoWrapper> FileSelectionStatus { get; set; } = new OperationStatus<FileSelectFileInfoWrapper> { Result = FileSelectFileInfoWrapper.Empty };

    public abstract OperationStatus<TParsingResult> FileParsingStatus { get; set; }

    public OperationStatus FileDataValidationStatus { get; set; } = new OperationStatus();

    public OperationStatus FileImportStatus { get; set; } = new OperationStatus();

    public string ErrorMessage
    {
        get
        {
            return FileSelectionStatus.Errors.FirstOrDefault() ??
                   FileParsingStatus.Errors.FirstOrDefault() ??
                   FileDataValidationStatus.Errors.FirstOrDefault() ??
                   FileImportStatus.Errors.FirstOrDefault() ?? string.Empty;
        }
    }
}
