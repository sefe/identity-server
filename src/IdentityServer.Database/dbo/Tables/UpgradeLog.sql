CREATE TABLE [dbo].[UpgradeLog] (
    [Id] INT NOT NULL IDENTITY(1,1),
    [Name] NVARCHAR(1024) NOT NULL, 
    [Type] NVARCHAR(50) NOT NULL, 
    [InsertedDateTime] DATETIME NOT NULL CONSTRAINT DF_UpgradeLog_InsertedDateTimeUtc DEFAULT SYSUTCDATETIME(),
    CONSTRAINT [PK_UpgradeLog_Id] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [UC_UpgradeLog_Name] UNIQUE NONCLUSTERED ([Name] ASC),
    CONSTRAINT [CH_UpgradeLog_Type] CHECK ([Type] = 'Post' OR [Type] = 'Pre')
);