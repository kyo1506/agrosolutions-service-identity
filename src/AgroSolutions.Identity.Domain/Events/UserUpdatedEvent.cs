namespace AgroSolutions.Identity.Domain.Events;

/// <summary>
/// Evento publicado quando um usuário é atualizado no sistema Identity
/// Será consumido pelo Properties Service para sincronizar produtores
/// </summary>
public class UserUpdatedEvent
{
    public Guid UserId { get; set; }
    public string? Email { get; set; }
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? Role { get; set; }
    public bool IsEnabled { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}
