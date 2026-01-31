namespace AgroSolutions.Identity.Domain.Events;

/// <summary>
/// Evento publicado quando um usuário é criado no sistema Identity
/// Será consumido pelo Properties Service para sincronizar produtores
/// </summary>
public class UserCreatedEvent
{
    public Guid UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? Role { get; set; }
    public bool IsEnabled { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}
