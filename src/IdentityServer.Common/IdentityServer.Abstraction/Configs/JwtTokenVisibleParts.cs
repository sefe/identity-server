namespace IdentityServer.Abstraction.Configs;

[Flags]
public enum JwtTokenVisibleParts
{
    None = 0,
    Header = 1,
    Payload = 2,
    All = Header | Payload
}
