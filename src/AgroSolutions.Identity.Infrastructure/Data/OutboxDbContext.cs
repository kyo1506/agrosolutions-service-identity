using AgroSolutions.Identity.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AgroSolutions.Identity.Infrastructure.Data;

/// <summary>
/// DbContext dedicado para o Outbox Pattern
/// Separado do contexto principal para melhor performance
/// </summary>
public class OutboxDbContext(DbContextOptions<OutboxDbContext> options) : DbContext(options)
{
    public DbSet<OutboxMessage> OutboxMessages { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<OutboxMessage>(entity =>
        {
            entity.HasKey(e => e.Id);

            entity.Property(e => e.EventType).IsRequired().HasMaxLength(500);

            entity.Property(e => e.Payload).IsRequired();

            entity.Property(e => e.CreatedAt).IsRequired();

            entity.Property(e => e.Status).IsRequired();

            entity.Property(e => e.ErrorMessage).HasMaxLength(2000);

            // Índices para melhorar performance de queries
            entity.HasIndex(e => new { e.Status, e.CreatedAt });

            entity.HasIndex(e => e.ProcessedAt);
        });
    }
}
