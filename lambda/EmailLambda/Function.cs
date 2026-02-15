using System.Text.Json;
using Amazon.Lambda.Core;
using Amazon.Lambda.SQSEvents;
using Amazon.SimpleEmail;
using Amazon.SimpleEmail.Model;

// Assembly attribute to enable Lambda JSON serialization
[assembly: LambdaSerializer(
    typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer)
)]

namespace AgroSolutions.EmailLambda;

/// <summary>
/// AWS Lambda para processar eventos de e-mail da fila SQS
/// Envia e-mails usando Amazon SES
/// </summary>
public class Function
{
    private readonly IAmazonSimpleEmailService _sesClient;
    private readonly string _fromEmail;
    private readonly string _fromName;

    public Function()
    {
        _sesClient = new AmazonSimpleEmailServiceClient();
        _fromEmail =
            Environment.GetEnvironmentVariable("FROM_EMAIL") ?? "noreply@agrosolutions.com.br";
        _fromName = Environment.GetEnvironmentVariable("FROM_NAME") ?? "AgroSolutions";
    }

    /// <summary>
    /// Handler principal da Lambda
    /// Processa mensagens da fila SQS e envia e-mails
    /// </summary>
    public async Task<SQSBatchResponse> FunctionHandler(SQSEvent sqsEvent, ILambdaContext context)
    {
        context.Logger.LogInformation($"Processing {sqsEvent.Records.Count} messages from SQS");

        var batchItemFailures = new List<SQSBatchResponse.BatchItemFailure>();

        foreach (var record in sqsEvent.Records)
        {
            try
            {
                context.Logger.LogInformation($"Processing message: {record.MessageId}");

                var emailEvent = JsonSerializer.Deserialize<SendEmailEvent>(
                    record.Body,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true }
                );

                if (emailEvent == null)
                {
                    throw new InvalidOperationException("Failed to deserialize email event");
                }

                await SendEmailAsync(emailEvent, context);

                context.Logger.LogInformation(
                    $"Successfully processed message: {record.MessageId}"
                );
            }
            catch (Exception ex)
            {
                context.Logger.LogError(
                    $"Error processing message {record.MessageId}: {ex.Message}"
                );

                // Adicionar mensagem falhada para retry
                batchItemFailures.Add(
                    new SQSBatchResponse.BatchItemFailure { ItemIdentifier = record.MessageId }
                );
            }
        }

        return new SQSBatchResponse { BatchItemFailures = batchItemFailures };
    }

    private async Task SendEmailAsync(SendEmailEvent emailEvent, ILambdaContext context)
    {
        context.Logger.LogInformation($"Sending email to: {emailEvent.To}");

        var sendRequest = new SendEmailRequest
        {
            Source = $"{_fromName} <{_fromEmail}>",
            Destination = new Destination { ToAddresses = new List<string> { emailEvent.To } },
            Message = new Message
            {
                Subject = new Content(emailEvent.Subject),
                Body = new Body
                {
                    Html = new Content { Charset = "UTF-8", Data = emailEvent.HtmlBody },
                    Text = !string.IsNullOrEmpty(emailEvent.TextBody)
                        ? new Content { Charset = "UTF-8", Data = emailEvent.TextBody }
                        : null,
                },
            },
        };

        // Adicionar Cc se houver
        if (emailEvent.Cc.Any())
        {
            sendRequest.Destination.CcAddresses = emailEvent.Cc;
        }

        // Adicionar Bcc se houver
        if (emailEvent.Bcc.Any())
        {
            sendRequest.Destination.BccAddresses = emailEvent.Bcc;
        }

        var response = await _sesClient.SendEmailAsync(sendRequest);

        context.Logger.LogInformation($"Email sent successfully. MessageId: {response.MessageId}");
    }
}

/// <summary>
/// Modelo do evento de e-mail
/// </summary>
public class SendEmailEvent
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
