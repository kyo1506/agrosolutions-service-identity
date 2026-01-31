namespace AgroSolutions.Identity.Domain.Interfaces;

/// <summary>
/// Interface para publicação de eventos de domínio
/// </summary>
public interface IEventPublisher
{
    Task PublishAsync<T>(T @event, CancellationToken cancellationToken = default)
        where T : class;
}
