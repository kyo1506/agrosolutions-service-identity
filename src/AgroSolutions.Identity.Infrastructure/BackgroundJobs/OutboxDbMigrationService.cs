using AgroSolutions.Identity.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AgroSolutions.Identity.Infrastructure.BackgroundJobs;

/// <summary>
/// Hosted service that applies OutboxDbContext migrations at startup.
/// Runs before OutboxProcessorJob processes messages.
/// </summary>
public class OutboxDbMigrationService(
    IServiceProvider serviceProvider,
    ILogger<OutboxDbMigrationService> logger
) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            logger.LogInformation("Applying OutboxDb migrations...");

            using var scope = serviceProvider.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<OutboxDbContext>();

            if (context.Database.IsRelational())
            {
                await context.Database.MigrateAsync(cancellationToken);
                logger.LogInformation("OutboxDb migrations applied successfully");
            }
            else
            {
                await context.Database.EnsureCreatedAsync(cancellationToken);
                logger.LogInformation("OutboxDb in-memory database created");
            }
        }
        catch (Exception ex)
        {
            logger.LogError(
                ex,
                "Failed to apply OutboxDb migrations. The OutboxProcessorJob may fail until the database is ready"
            );
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
