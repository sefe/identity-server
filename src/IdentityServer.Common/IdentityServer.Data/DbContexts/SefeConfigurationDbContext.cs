// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using Duende.IdentityServer.EntityFramework.DbContexts;
using Microsoft.EntityFrameworkCore;
using IdentityServer.Abstraction;
using IdentityServer.Abstraction.Contracts;
using IdentityServer.Abstraction.Entities.IdentityServerConfig;
using IdentityServer.Abstraction.Entities.IdentityServerConfig.SystemPermissions;
using IdentityServer.Data.DuendeEntityExtensions;
using IdentityServer.Data.Entities.Roles;

namespace IdentityServer.Data.DbContexts;

public class IdentityServerConfigurationDbContext : ConfigurationDbContext<IdentityServerConfigurationDbContext>
{
    private readonly ICurrentUserService? _currentUserService;

    public IdentityServerConfigurationDbContext(DbContextOptions<IdentityServerConfigurationDbContext> options, ICurrentUserService? currentUserService)
        : base(options)
    {
        _currentUserService = currentUserService;
    }

    public DbSet<RoleMapping> RoleMappings { get; set; }

    public DbSet<ApiResourceRole> ApiResourceRoles { get; set; }

    public DbSet<RoleMappingType> RoleMappingTypes { get; set; }

    public DbSet<SystemPermission> SystemPermissions { get; set; }

    public DbSet<SystemPermissionEnvironment> SystemPermissionEnvironments { get; set; }

    public DbSet<SystemPermissionRole> SystemPermissionRole { get; set; }

    public new DbSet<ApiResourceExt> ApiResources { get; set; }
    public DbSet<ApiResourceScopeExt> ApiResourceScopes { get; set; }
    public DbSet<ApiResourceSecretExt> ApiResourceSecrets { get; set; }

    public new DbSet<ApiScopeExt> ApiScopes { get; set; }

    public new DbSet<ClientExt> Clients { get; set; }
    public new DbSet<ClientCorsOriginExt> ClientCorsOrigins { get; set; }
    public DbSet<ClientGrantTypeExt> ClientGrantTypes { get; set; }
    public DbSet<ClientRedirectUriExt> ClientRedirectUris { get; set; }
    public DbSet<ClientPostLogoutRedirectUriExt> ClientPostLogoutRedirectUris { get; set; }
    public DbSet<ClientSecretExt> ClientSecrets { get; set; }
    public DbSet<ClientScopeExt> ClientScopes { get; set; }
    public DbSet<ClientRole> ClientRoles { get; set; }
    public DbSet<ClientRoleMapping> ClientRoleMappings { get; set; }
    public DbSet<ClientEntraApp> ClientEntraApps { get; set; }

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        var currentTime = DateTime.UtcNow;

        // Automatically set Created data for entities implementing IHasCreatedInfo
        var entries = ChangeTracker.Entries()
            .Where(e => e.State == EntityState.Added && e.Entity is IHasCreatedInfo);
        foreach (var entry in entries)
        {
            var createdInfo = (IHasCreatedInfo)entry.Entity;
            createdInfo.Created = currentTime;
            createdInfo.CreatedBy = _currentUserService?.UserName;
        }

        // Automatically set Updated data for entities implementing IHasUpdatedInfo
        var updatedEntries = ChangeTracker.Entries()
            .Where(e => e.State == EntityState.Modified && e.Entity is IHasUpdatedInfo);
        foreach (var entry in updatedEntries)
        {
            var updatedInfo = (IHasUpdatedInfo)entry.Entity;
            updatedInfo.Updated = currentTime;
            updatedInfo.UpdatedBy = _currentUserService?.UserName;
        }

        return base.SaveChangesAsync(cancellationToken);
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {

        modelBuilder.Entity<RoleMapping>().HasKey(k => k.Id);
        modelBuilder.Entity<ApiResourceRole>().HasKey(k => k.Id);
        modelBuilder.Entity<RoleMappingType>().HasKey(k => k.Id);

        modelBuilder.Entity<SystemPermissionEnvironment>().HasKey(k => k.Id);
        modelBuilder.Entity<SystemPermission>().HasKey(k => k.Id);
        modelBuilder.Entity<SystemPermissionRole>().HasKey(k => k.Id);

        modelBuilder.Entity<SystemPermission>().Property(e => e.Name).HasMaxLength(100);
        modelBuilder.Entity<SystemPermission>().Property(t => t.Created).IsRequired().HasDefaultValueSql("GETUTCDATE()");
        modelBuilder.Entity<SystemPermissionRole>().Property(e => e.Name).HasMaxLength(255);
        modelBuilder.Entity<SystemPermissionRole>().Property(e => e.RoleType).IsRequired().HasConversion<int>();

        modelBuilder.Entity<RoleMapping>().Property(r => r.MappingType).HasConversion<int>();
        modelBuilder.Entity<RoleMapping>().Property(e => e.Value).HasMaxLength(250);
        modelBuilder.Entity<RoleMapping>().Property(e => e.Description).HasMaxLength(400);

        modelBuilder.Entity<RoleMappingType>().Property(e => e.Name).HasMaxLength(100);
        modelBuilder.Entity<ApiResourceRole>().Property(e => e.RoleName).HasMaxLength(100);

        modelBuilder.Entity<ClientRole>().HasKey(k => k.Id);
        modelBuilder.Entity<ClientRole>().Property(e => e.RoleName).IsRequired().HasMaxLength(100);

        modelBuilder.Entity<ClientRoleMapping>().HasKey(k => k.Id);
        modelBuilder.Entity<ClientRoleMapping>().Property(r => r.MappingType).HasConversion<int>();
        modelBuilder.Entity<ClientRoleMapping>().Property(e => e.Value).HasMaxLength(250);
        modelBuilder.Entity<ClientRoleMapping>().Property(e => e.Description).HasMaxLength(400);

        modelBuilder.Entity<ClientEntraApp>().HasKey(k => k.Id);
        modelBuilder.Entity<ClientEntraApp>().Property(e => e.AppId).HasMaxLength(50);
        modelBuilder.Entity<ClientEntraApp>().Property(e => e.AppName).HasMaxLength(300);

        modelBuilder.Entity<ClientExt>()
            .HasOne(x => x.SystemPermissionEnvironment) // One ClientExt has One SystemPermissionEnvironment
            .WithMany() // One SystemPermissionEnvironment has MANY ClientExt
            .HasForeignKey(r => r.SystemPermissionEnvironmentId)
            .OnDelete(DeleteBehavior.NoAction); //if SystemPermissionEnvironment deleted, ClientExt is preserved.

        modelBuilder.Entity<ClientEntraApp>()
            .HasOne(r => r.Client) // One ClientEntraApp has One ClientExt
            .WithMany(arr => arr.EntraApps) // One ClientExt has MANY ClientEntraApp
            .HasForeignKey(r => r.ClientId)
            .OnDelete(DeleteBehavior.Cascade); //if ClientExt deleted, all associated ClientEntraApp deleted.

        modelBuilder.Entity<ClientRole>()
            .HasOne(r => r.Client) // One ClientRole has One ClientExt
            .WithMany(arr => arr.Roles) // One ClientExt has MANY ClientRole
            .HasForeignKey(r => r.ClientId)
            .OnDelete(DeleteBehavior.Cascade); //if ClientExt deleted, all associated ClientRole deleted.

        // Create FK [ClientRoleMapping].[ClientRoleId] --> [ClientRole].[Id]
        modelBuilder.Entity<ClientRoleMapping>()
            .HasOne(r => r.Role)                // one ClientRoleMapping has One ClientRole
            .WithMany(arr => arr.Mappings)      // one ClientRole has MANY ClientRoleMapping
            .HasForeignKey(r => r.ClientRoleId)
            .OnDelete(DeleteBehavior.Cascade);  // If ClientRole is deleted, delete all ClientRoleMappings

        modelBuilder.Entity<ApiResourceExt>()
            .HasOne(x => x.SystemPermissionEnvironment) // One ApiResourceExt has One SystemPermissionEnvironment
            .WithMany() // One SystemPermissionEnvironment has MANY ApiResourceExt
            .HasForeignKey(r => r.SystemPermissionEnvironmentId)
            .OnDelete(DeleteBehavior.NoAction); //if SystemPermissionEnvironment deleted, ApiResourceExt is preserved.

        modelBuilder.Entity<SystemPermissionEnvironment>()
            .HasOne(t => t.SystemPermission)  // Each SystemPermissionEnvironment belongs to one SystemPermission
            .WithMany(t => t.Environments) // A SystemPermission has many SystemPermissionEnvironments
            .HasForeignKey(t => t.SystemPermissionId)
            .OnDelete(DeleteBehavior.Cascade); // If a SystemPermission is deleted, delete its associated SystemPermissionEnvironments

        modelBuilder.Entity<SystemPermissionRole>()
            .HasOne<SystemPermissionEnvironment>()  // Each SystemPermission belongs to one SystemPermissionEnvironment
            .WithMany(t => t.Permissions) // A SystemPermissionEnvironments has many SystemPermission
            .HasForeignKey(t => t.SystemPermissionEnvironmentId)
            .OnDelete(DeleteBehavior.Cascade); // If a SystemPermissionEnvironment is deleted, delete its associated SystemPermissionRole

        modelBuilder.Entity<ApiResourceRole>()
            .HasOne(r => r.ApiResource) // One ApiResourceRole has One ApiResourceExt
            .WithMany(arr => arr.Roles) // One ApiResourceExt has MANY ApiResourceRole
            .HasForeignKey(r => r.ApiResourceId)
            .OnDelete(DeleteBehavior.Cascade); //if ApiResourceExt deleted, all associated ApiResourceRole deleted.

        // Create FK [RoleMapping].[ApiResourceRoleId] --> [ApiResourceRole][Id]
        modelBuilder.Entity<RoleMapping>()
            .HasOne(r => r.Role)
            .WithMany(arr => arr.Mappings) // one ApiResourceRole has MANY RoleMapping
            .HasForeignKey(r => r.ApiResourceRoleId)
            .OnDelete(DeleteBehavior.Cascade); // If ApiResourceRole is deleted, delete all RoleMappings

        // Create FK [RoleMapping].[RoleMappingTypeId] --> [RoleMappingType][Id]
        modelBuilder.Entity<RoleMapping>()
            .HasOne<RoleMappingType>() // Each RoleMapping is linked to one RoleMappingType
            .WithMany() // one RoleMappingType has MANY RoleMappings
            .HasForeignKey(r => r.RoleMappingTypeId)
            .OnDelete(DeleteBehavior.NoAction); // if RoleMapping deleted,  RoleMappingType is preserved.

        // Seed Data for Reference Table
        modelBuilder.Entity<RoleMappingType>().HasData(
            new RoleMappingType { Id = (int)RoleMapType.SecurityGroup, Name = "Entis Security Group ID" },
            new RoleMappingType { Id = (int)RoleMapType.ClientId, Name = "Client Id" },
            new RoleMappingType { Id = (int)RoleMapType.UserObjectId, Name = "User Object Id" }
        );

        // Map temporal period columns for Client
        ConfigurePeriodProperties<ClientExt>(modelBuilder);
        ConfigurePeriodProperties<ClientRole>(modelBuilder);
        ConfigurePeriodProperties<ClientRoleMapping>(modelBuilder);
        ConfigurePeriodProperties<ClientSecretExt>(modelBuilder);
        ConfigurePeriodProperties<ClientScopeExt>(modelBuilder);
        ConfigurePeriodProperties<ClientRedirectUriExt>(modelBuilder);
        ConfigurePeriodProperties<ClientPostLogoutRedirectUriExt>(modelBuilder);
        ConfigurePeriodProperties<ClientGrantTypeExt>(modelBuilder);
        ConfigurePeriodProperties<ClientCorsOriginExt>(modelBuilder);
        ConfigurePeriodProperties<ClientEntraApp>(modelBuilder);

        // Map temporal period columns for ApiResource
        ConfigurePeriodProperties<ApiResourceExt>(modelBuilder);
        ConfigurePeriodProperties<ApiResourceScopeExt>(modelBuilder);
        ConfigurePeriodProperties<ApiResourceSecretExt>(modelBuilder);
        ConfigurePeriodProperties<ApiScopeExt>(modelBuilder);
        ConfigurePeriodProperties<ApiResourceRole>(modelBuilder);
        ConfigurePeriodProperties<RoleMapping>(modelBuilder);

        // Map temporal period columns for SystemPermission entities
        ConfigurePeriodProperties<SystemPermission>(modelBuilder);
        ConfigurePeriodProperties<SystemPermissionEnvironment>(modelBuilder);
        ConfigurePeriodProperties<SystemPermissionRole>(modelBuilder);

        base.OnModelCreating(modelBuilder);
    }

    private static void ConfigurePeriodProperties<TEntity>(ModelBuilder modelBuilder) where TEntity : class, IHasPeriodData
    {
        modelBuilder.Entity<TEntity>()
            .Property(c => c.ValidFrom)
            .ValueGeneratedOnAddOrUpdate();
        modelBuilder.Entity<TEntity>()
            .Property(c => c.ValidTo)
            .ValueGeneratedOnAddOrUpdate();
    }
}
