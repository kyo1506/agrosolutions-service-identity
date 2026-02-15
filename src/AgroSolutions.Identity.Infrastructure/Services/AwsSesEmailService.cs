using AgroSolutions.Identity.Domain.Interfaces;
using Amazon.SimpleEmail;
using Amazon.SimpleEmail.Model;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace AgroSolutions.Identity.Infrastructure.Services;

/// <summary>
/// Implementação do serviço de e-mail usando Amazon SES
/// </summary>
public class AwsSesEmailService : IEmailService
{
    private readonly IAmazonSimpleEmailService _sesClient;
    private readonly ILogger<AwsSesEmailService> _logger;
    private readonly string _fromEmail;
    private readonly string _fromName;

    public AwsSesEmailService(
        IAmazonSimpleEmailService sesClient,
        IConfiguration configuration,
        ILogger<AwsSesEmailService> logger
    )
    {
        _sesClient = sesClient;
        _logger = logger;
        _fromEmail = configuration["AWS:SES:FromEmail"] ?? "noreply@agrosolutions.com.br";
        _fromName = configuration["AWS:SES:FromName"] ?? "AgroSolutions";
    }

    public async Task<bool> SendEmailAsync(
        string to,
        string subject,
        string htmlBody,
        string? textBody = null,
        CancellationToken cancellationToken = default
    )
    {
        try
        {
            var sendRequest = new SendEmailRequest
            {
                Source = $"{_fromName} <{_fromEmail}>",
                Destination = new Destination { ToAddresses = new List<string> { to } },
                Message = new Message
                {
                    Subject = new Content(subject),
                    Body = new Body
                    {
                        Html = new Content { Charset = "UTF-8", Data = htmlBody },
                        Text = !string.IsNullOrEmpty(textBody)
                            ? new Content { Charset = "UTF-8", Data = textBody }
                            : null,
                    },
                },
            };

            var response = await _sesClient.SendEmailAsync(sendRequest, cancellationToken);

            _logger.LogInformation(
                "Email sent successfully to {To}. MessageId: {MessageId}",
                to,
                response.MessageId
            );

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send email to {To}. Subject: {Subject}", to, subject);
            return false;
        }
    }

    public async Task<bool> SendTemplatedEmailAsync(
        string to,
        string templateName,
        Dictionary<string, string> templateData,
        CancellationToken cancellationToken = default
    )
    {
        try
        {
            var sendRequest = new SendTemplatedEmailRequest
            {
                Source = $"{_fromName} <{_fromEmail}>",
                Destination = new Destination { ToAddresses = new List<string> { to } },
                Template = templateName,
                TemplateData = System.Text.Json.JsonSerializer.Serialize(templateData),
            };

            var response = await _sesClient.SendTemplatedEmailAsync(sendRequest, cancellationToken);

            _logger.LogInformation(
                "Templated email sent successfully to {To} using template {TemplateName}. MessageId: {MessageId}",
                to,
                templateName,
                response.MessageId
            );

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Failed to send templated email to {To}. Template: {TemplateName}",
                to,
                templateName
            );
            return false;
        }
    }

    public async Task<bool> SendWelcomeEmailAsync(
        string to,
        string firstName,
        CancellationToken cancellationToken = default
    )
    {
        var htmlBody =
            $@"
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background-color: #4CAF50; color: white; padding: 20px; text-align: center; }}
        .content {{ padding: 20px; background-color: #f9f9f9; }}
        .footer {{ text-align: center; padding: 20px; font-size: 12px; color: #666; }}
    </style>
</head>
<body>
    <div class=""container"">
        <div class=""header"">
            <h1>Bem-vindo ao AgroSolutions! </h1>
        </div>
        <div class=""content"">
            <h2>Olá, {firstName}!</h2>
            <p>Estamos muito felizes em tê-lo(a) conosco.</p>
            <p>Sua conta foi criada com sucesso. Você já pode acessar nossa plataforma e começar a gerenciar suas propriedades rurais com inteligência e tecnologia.</p>
            <p>Se precisar de ajuda, nossa equipe de suporte está sempre disponível.</p>
            <p><strong>Equipe AgroSolutions</strong></p>
        </div>
        <div class=""footer"">
            <p>© 2026 AgroSolutions. Todos os direitos reservados.</p>
        </div>
    </div>
</body>
</html>";

        var textBody =
            $@"
Bem-vindo ao AgroSolutions!

Olá, {firstName}!

Estamos muito felizes em tê-lo(a) conosco.

Sua conta foi criada com sucesso. Você já pode acessar nossa plataforma e começar a gerenciar suas propriedades rurais.

Se precisar de ajuda, nossa equipe está sempre disponível.

Equipe AgroSolutions
";

        return await SendEmailAsync(
            to,
            "Bem-vindo ao AgroSolutions!",
            htmlBody,
            textBody,
            cancellationToken
        );
    }
}
