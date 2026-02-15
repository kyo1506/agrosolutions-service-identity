namespace AgroSolutions.Identity.Domain.Interfaces;

/// <summary>
/// Interface para serviço de envio de e-mails
/// Implementação: AwsSesEmailService (Amazon SES)
/// </summary>
public interface IEmailService
{
    /// <summary>
    /// Envia um e-mail simples
    /// </summary>
    Task<bool> SendEmailAsync(
        string to,
        string subject,
        string htmlBody,
        string? textBody = null,
        CancellationToken cancellationToken = default
    );

    /// <summary>
    /// Envia um e-mail usando template pré-configurado no SES
    /// </summary>
    Task<bool> SendTemplatedEmailAsync(
        string to,
        string templateName,
        Dictionary<string, string> templateData,
        CancellationToken cancellationToken = default
    );

    /// <summary>
    /// Envia e-mail de boas-vindas após registro
    /// </summary>
    Task<bool> SendWelcomeEmailAsync(
        string to,
        string firstName,
        CancellationToken cancellationToken = default
    );
}
