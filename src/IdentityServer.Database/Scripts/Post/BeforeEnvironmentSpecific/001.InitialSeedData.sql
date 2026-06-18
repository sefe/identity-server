PRINT 'Running script to seed static data...'

IF (NOT EXISTS (SELECT 1 FROM [dbo].[SystemPermissions] WHERE [Name] = N'identity-server'))
BEGIN
	SET IDENTITY_INSERT [dbo].[SystemPermissions] ON
	INSERT INTO [dbo].[SystemPermissions] ([Id], [Name], [Description], [Updated], [Created]) VALUES (1, N'identity-server', N'OpenID Connect and OAuth 2.0 service', NULL, SYSUTCDATETIME())
	SET IDENTITY_INSERT [dbo].[SystemPermissions] OFF
END

IF (NOT EXISTS (SELECT 1 FROM [dbo].[SystemPermissionEnvironments] WHERE [Environment] = N'Development'))
BEGIN

	SET IDENTITY_INSERT [dbo].[SystemPermissionEnvironments] ON
	INSERT INTO [dbo].[SystemPermissionEnvironments] ([Id], [Environment], [SystemPermissionId]) VALUES (1, N'Development', 1)
	INSERT INTO [dbo].[SystemPermissionEnvironments] ([Id], [Environment], [SystemPermissionId]) VALUES (2, N'Production', 1)
	INSERT INTO [dbo].[SystemPermissionEnvironments] ([Id], [Environment], [SystemPermissionId]) VALUES (3, N'Pre Production', 1)
	SET IDENTITY_INSERT [dbo].[SystemPermissionEnvironments] OFF
END

IF (NOT EXISTS (SELECT 1 FROM [dbo].[RoleMappingTypes] WHERE [Name] = N'Entis Security Group ID'))
BEGIN
	SET IDENTITY_INSERT [dbo].[RoleMappingTypes] ON
	INSERT INTO [dbo].[RoleMappingTypes] ([Id], [Name]) VALUES (1, N'Entis Security Group ID')
	INSERT INTO [dbo].[RoleMappingTypes] ([Id], [Name]) VALUES (2, N'Client Id')
	INSERT INTO [dbo].[RoleMappingTypes] ([Id], [Name]) VALUES (3, N'User Object Id')
	SET IDENTITY_INSERT [dbo].[RoleMappingTypes] OFF
END

PRINT 'Running script to seed static data...Finished'
