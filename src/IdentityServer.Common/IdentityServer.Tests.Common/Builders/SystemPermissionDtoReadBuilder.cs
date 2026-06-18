using IdentityServer.Abstraction.DTO.SystemPermissions;

namespace IdentityServer.Tests.Common.Builders;

public class SystemPermissionDtoReadBuilder
{
    private static int _uniqueIdCounter = 0;

    private readonly SystemPermissionDtoRead _systemPermission;

    public SystemPermissionDtoReadBuilder()
    {
        _systemPermission = new SystemPermissionDtoRead
        {
            Id = Interlocked.Increment(ref _uniqueIdCounter),
            Name = "TestSysPermission",
            Description = "Test Description"
        };
    }

    public SystemPermissionDtoReadBuilder WithName(string name)
    {
        _systemPermission.Name = name;
        return this;
    }

    public SystemPermissionDtoReadBuilder WithDescription(string description)
    {
        _systemPermission.Description = description;
        return this;
    }

    public SystemPermissionEnvironmentDtoReadBuilder AddEnvironment(string environment)
    {
        return new SystemPermissionEnvironmentDtoReadBuilder(this, _systemPermission.Id, _systemPermission.Name, environment);
    }

    public SystemPermissionDtoReadBuilder AddEnvironment(SystemPermissionEnvironmentDtoRead env)
    {
        _systemPermission.Environments.Add(env);
        return this;
    }

    public SystemPermissionDtoRead Build()
    {
        return _systemPermission;
    }
}
