using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Text.Json;
using AgroSolutions.Identity.Domain.Entities;
using AgroSolutions.Identity.Domain.Interfaces;
using AgroSolutions.Identity.Infrastructure.Data;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Polly;
using Polly.CircuitBreaker;

namespace AgroSolutions.Identity.Infrastructure.Messaging;

/// <summary>
/// EventPublisher com recursos avançados:
/// - Circuit Breaker para proteção contra falhas em cascata
/// - Outbox Pattern para garantir exactly-once delivery
/// - Métricas OpenTelemetry para observabilidade
/// - Retry policy gerenciado pelo MassTransit
/// </summary>
public class ResilientEventPublisher : IEventPublisher
{
    private readonly IPublishEndpoint _publishEndpoint;
    private readonly OutboxDbContext _outboxContext;
    private readonly ILogger<ResilientEventPublisher> _logger;
    private readonly AsyncCircuitBreakerPolicy _circuitBreakerPolicy;
    private readonly ActivitySource _activitySource;
    private readonly Counter<long> _eventsPublishedCounter;
    private readonly Counter<long> _eventsFailedCounter;
    private readonly Histogram<double> _publishDurationHistogram;

    public ResilientEventPublisher(
        IPublishEndpoint publishEndpoint,
        OutboxDbContext outboxContext,
        ILogger<ResilientEventPublisher> logger,
        Meter meter
    )
    {
        _publishEndpoint = publishEndpoint;
        _outboxContext = outboxContext;
        _logger = logger;
        _activitySource = new ActivitySource("AgroSolutions.Identity.Messaging");

        // Configurar Circuit Breaker
        _circuitBreakerPolicy = Policy
            .Handle<Exception>()
            .CircuitBreakerAsync(
                exceptionsAllowedBeforeBreaking: 5,
                durationOfBreak: TimeSpan.FromSeconds(30),
                onBreak: (exception, duration) =>
                {
                    _logger.LogWarning(
                        exception,
                        "Circuit breaker opened for {DurationSeconds}s due to consecutive failures",
                        duration.TotalSeconds
                    );
                },
                onReset: () =>
                {
                    _logger.LogInformation("Circuit breaker reset - connection restored");
                },
                onHalfOpen: () =>
                {
                    _logger.LogInformation("Circuit breaker half-open - testing connection");
                }
            );

        // Configurar métricas OpenTelemetry
        _eventsPublishedCounter = meter.CreateCounter<long>(
            "events.published",
            description: "Total number of events successfully published"
        );

        _eventsFailedCounter = meter.CreateCounter<long>(
            "events.failed",
            description: "Total number of events that failed to publish"
        );

        _publishDurationHistogram = meter.CreateHistogram<double>(
            "events.publish.duration",
            unit: "ms",
            description: "Duration of event publishing operations"
        );
    }

    public async Task PublishAsync<T>(T @event, CancellationToken cancellationToken = default)
        where T : class
    {
        var eventType = typeof(T).FullName ?? typeof(T).Name;
        var stopwatch = Stopwatch.StartNew();

        using var activity = _activitySource.StartActivity("PublishEvent");
        activity?.SetTag("event.type", eventType);

        try
        {
            // Passo 1: Salvar no Outbox (transacional)
            var outboxMessage = new OutboxMessage
            {
                Id = Guid.NewGuid(),
                EventType = eventType,
                Payload = JsonSerializer.Serialize(@event),
                CreatedAt = DateTime.UtcNow,
                Status = OutboxMessageStatus.Pending,
                RetryCount = 0,
            };

            await _outboxContext.OutboxMessages.AddAsync(outboxMessage, cancellationToken);
            await _outboxContext.SaveChangesAsync(cancellationToken);

            _logger.LogDebug(
                "Event {EventType} saved to outbox with ID {OutboxId}",
                eventType,
                outboxMessage.Id
            );

            // Passo 2: Tentar publicar imediatamente com Circuit Breaker
            await _circuitBreakerPolicy.ExecuteAsync(async () =>
            {
                await _publishEndpoint.Publish(@event, cancellationToken);

                // Marcar como processado
                outboxMessage.Status = OutboxMessageStatus.Processed;
                outboxMessage.ProcessedAt = DateTime.UtcNow;
                await _outboxContext.SaveChangesAsync(cancellationToken);

                _logger.LogInformation(
                    "Event {EventType} published successfully (OutboxId: {OutboxId})",
                    eventType,
                    outboxMessage.Id
                );
            });

            stopwatch.Stop();

            // Registrar métricas de sucesso
            _eventsPublishedCounter.Add(
                1,
                new KeyValuePair<string, object?>("event.type", eventType)
            );
            _publishDurationHistogram.Record(
                stopwatch.ElapsedMilliseconds,
                new KeyValuePair<string, object?>("event.type", eventType)
            );

            activity?.SetStatus(ActivityStatusCode.Ok);
        }
        catch (BrokenCircuitException ex)
        {
            stopwatch.Stop();

            _logger.LogWarning(
                ex,
                "Circuit breaker is open - event {EventType} will be processed by background worker",
                eventType
            );

            _eventsFailedCounter.Add(
                1,
                new KeyValuePair<string, object?>("event.type", eventType),
                new KeyValuePair<string, object?>("failure.reason", "circuit_breaker_open")
            );

            activity?.SetStatus(ActivityStatusCode.Error, "Circuit breaker open");

            // Evento já está no outbox, será processado pelo background worker
        }
        catch (Exception ex)
        {
            stopwatch.Stop();

            _logger.LogError(
                ex,
                "Failed to publish event {EventType} - will retry via background worker",
                eventType
            );

            _eventsFailedCounter.Add(
                1,
                new KeyValuePair<string, object?>("event.type", eventType),
                new KeyValuePair<string, object?>("failure.reason", ex.GetType().Name)
            );

            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);

            // Evento permanece no outbox para retry posterior
            throw;
        }
    }
}
