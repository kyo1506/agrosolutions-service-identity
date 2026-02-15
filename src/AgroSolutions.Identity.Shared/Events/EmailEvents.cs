using System;
using System.Collections.Generic;

namespace AgroSolutions.Identity.Shared.Events;

/// <summary>
/// Evento publicado quando um e-mail precisa ser enviado
/// Processado por Lambda via SQS
/// </summary>
public record SendEmailEvent
{
    public required string To { get; init; }
    public required string Subject { get; init; }
    public required string HtmlBody { get; init; }
    public string? TextBody { get; init; }
    public string? From { get; init; }
    public List<string> Cc { get; init; } = new();
    public List<string> Bcc { get; init; } = new();
    public Dictionary<string, string> Metadata { get; init; } = new();
    public string CorrelationId { get; init; } = Guid.NewGuid().ToString();
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
}

/// <summary>
/// Evento de e-mail de boas-vindas após registro
/// </summary>
public record WelcomeEmailEvent
{
    public required string UserId { get; init; }
    public required string Email { get; init; }
    public required string FirstName { get; init; }
    public required string LastName { get; init; }
    public DateTime RegisteredAt { get; init; } = DateTime.UtcNow;
}

/// <summary>
/// Evento de e-mail de redefinição de senha
/// </summary>
public record PasswordResetEmailEvent
{
    public required string UserId { get; init; }
    public required string Email { get; init; }
    public required string ResetToken { get; init; }
    public required string ResetUrl { get; init; }
    public DateTime RequestedAt { get; init; } = DateTime.UtcNow;
    public DateTime ExpiresAt { get; init; }
}

/// <summary>
/// Evento de confirmação de e-mail
/// </summary>
public record EmailVerificationEvent
{
    public required string UserId { get; init; }
    public required string Email { get; init; }
    public required string VerificationToken { get; init; }
    public required string VerificationUrl { get; init; }
    public DateTime RequestedAt { get; init; } = DateTime.UtcNow;
}
