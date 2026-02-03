using Microsoft.EntityFrameworkCore;
using Swedwise.NodiniteXTArchiveManager.Models;

public class MetainfDbContext(DbContextOptions<MetainfDbContext> options) : DbContext(options)
{
    public DbSet<MetainfFileEntity> Metainfs { get; set; } = null!;

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<MetainfFileEntity>().ToTable("Metainfs", "dbo");
    }
}
