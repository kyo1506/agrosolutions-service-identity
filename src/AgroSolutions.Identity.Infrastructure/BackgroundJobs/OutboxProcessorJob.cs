using System.Text.Json;
using AgroSolutions.Identity.Domain.Entities;
using AgroSolutions.Identity.Infrastructure.Data;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AgroSolutions.Identity.Infrastructure.BackgroundJobs;

/// <summary>
/// Background worker que processa mensagens pendentes no Outbox
/// Implementa retry com exponential backoff e move mensagens falhadas para status Failed
/// </summary>
public class OutboxProcessorJob(
    IServiceProvider serviceProvider,
    ILogger<OutboxProcessorJob> logger
) : BackgroundService
{
    private readonly IServiceProvider _serviceProvider = serviceProvider;
    private readonly ILogger<OutboxProcessorJob> _logger = logger;
    private readonly TimeSpan _processingInterval = TimeSpan.FromSeconds(10);
    private const int MaxRetryCount = 5;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Outbox Processor Job started");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ProcessPendingMessagesAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing outbox messages");
            }

            await Task.Delay(_processingInterval, stoppingToken);
        }

        _logger.LogInformation("Outbox Processor Job stopped");
    }

    private async Task ProcessPendingMessagesAsync(CancellationToken cancellationToken)
    {
        using var scope = _serviceProvider.CreateScope();
        var outboxContext = scope.ServiceProvider.GetRequiredService<OutboxDbContext>();
        var publishEndpoint = scope.ServiceProvider.GetRequiredService<IPublishEndpoint>();

        var pendingMessages = await outboxContext
            .OutboxMessages.Where(m =>
                (
                    m.Status == OutboxMessageStatus.Pending
                    || m.Status == OutboxMessageStatus.Processing
                )
                && m.RetryCount < MaxRetryCount
            )
            .OrderBy(m => m.CreatedAt)
            .Take(100) // Processar em lotes
            .ToListAsync(cancellationToken);

        if (pendingMessages.Count == 0)
        {
            return;
        }

        _logger.LogInformation("Processing {Count} pending outbox messages", pendingMessages.Count);

        foreach (var message in pendingMessages)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                break;
            }

            await ProcessSingleMessageAsync(
                message,
                publishEndpoint,
                outboxContext,
                cancellationToken
            );
        }

        await outboxContext.SaveChangesAsync(cancellationToken);
    }

    private async Task ProcessSingleMessageAsync(
        OutboxMessage message,
        IPublishEndpoint publishEndpoint,
        OutboxDbContext outboxContext,
        CancellationToken cancellationToken
    )
    {
        if (message.RetryCount > 0)
        {
            var delaySeconds = Math.Pow(2, message.RetryCount - 1) * 5; // 5s, 10s, 20s, 40s, 80s
            var timeSinceLastAttempt = DateTime.UtcNow - message.CreatedAt;

            if (timeSinceLastAttempt.TotalSeconds < delaySeconds)
            {
                _logger.LogDebug(
                    "Skipping message {MessageId} - waiting for backoff period ({DelaySeconds}s)",
                    message.Id,
                    delaySeconds
                );
                return;
            }
        }

        try
        {
            message.Status = OutboxMessageStatus.Processing;
            message.RetryCount++;

            _logger.LogDebug(
                "Publishing outbox message {MessageId} of type {EventType} (attempt {RetryCount}/{MaxRetryCount})",
                message.Id,
                message.EventType,
                message.RetryCount,
                MaxRetryCount
            );

            var eventType =
                Type.GetType(message.EventType)
                ?? throw new InvalidOperationException(
                    $"Event type '{message.EventType}' not found"
                );
            var @event =
                JsonSerializer.Deserialize(message.Payload, eventType)
                ?? throw new InvalidOperationException(
                    $"Failed to deserialize event of type '{message.EventType}'"
                );

            // Use the generic Publish<T> path via reflection so MassTransit's SQS transport
            // initializes the MessageAttributes dictionary correctly. The non-generic
            // Publish(object, Type) overload leaves the header adapter context uninitialized,
            // causing NullReferenceException inside TransportSetHeaderAdapter.
            var publishMethod = typeof(IPublishEndpoint)
                .GetMethods()
                .First(m =>
                    m.Name == nameof(IPublishEndpoint.Publish)
                    && m.IsGenericMethod
                    && m.GetParameters().Length == 2
                    && m.GetParameters()[1].ParameterType == typeof(CancellationToken)
                )
                .MakeGenericMethod(eventType);

            await (Task)publishMethod.Invoke(publishEndpoint, [@event, cancellationToken])!;

            message.Status = OutboxMessageStatus.Processed;
            message.ProcessedAt = DateTime.UtcNow;
            message.ErrorMessage = null;

            _logger.LogInformation(
                "Successfully published outbox message {MessageId} of type {EventType}",
                message.Id,
                message.EventType
            );
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Failed to publish outbox message {MessageId} of type {EventType} (attempt {RetryCount}/{MaxRetryCount})",
                message.Id,
                message.EventType,
                message.RetryCount,
                MaxRetryCount
            );

            message.ErrorMessage = ex.Message;

            if (message.RetryCount >= MaxRetryCount)
            {
                message.Status = OutboxMessageStatus.Failed;
                _logger.LogWarning(
                    "Outbox message {MessageId} moved to Failed status after {MaxRetryCount} attempts",
                    message.Id,
                    MaxRetryCount
                );
            }
            else
            {
                message.Status = OutboxMessageStatus.Pending;
            }
        }
    }
}
