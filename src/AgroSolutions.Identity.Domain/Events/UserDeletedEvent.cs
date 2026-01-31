namespace AgroSolutions.Identity.Domain.Events;

/// <summary>
/// Evento publicado quando um usuário é desabilitado (soft delete) no sistema Identity
/// Será consumido pelo Properties Service para marcar produtor como inativo
/// </summary>
public class UserDeletedEvent
{
    public Guid UserId { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}
