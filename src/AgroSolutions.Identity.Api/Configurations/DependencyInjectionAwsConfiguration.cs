using AgroSolutions.Identity.Api.Extensions;
using AgroSolutions.Identity.Domain.Interfaces;
using AgroSolutions.Identity.Domain.Notifications;
using AgroSolutions.Identity.Infrastructure.BackgroundJobs;
using AgroSolutions.Identity.Infrastructure.Data;
using AgroSolutions.Identity.Infrastructure.Extensions;
using AgroSolutions.Identity.Infrastructure.Messaging;
using AgroSolutions.Identity.Infrastructure.Services;
using Amazon.SimpleEmail;
using Amazon.SQS;
using MassTransit;
using Microsoft.EntityFrameworkCore;

namespace AgroSolutions.Identity.Api.Configurations;

public static class DependencyInjectionAwsConfiguration
{
    /// <summary>
    /// Configuração para usar AWS SQS/SNS em produção
    /// Credenciais via variáveis de ambiente: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN
    /// </summary>
    public static void ResolveAwsDependencies(
        this IServiceCollection services,
        IConfiguration configuration
    )
    {
        // Domain
        services.AddScoped<INotifier, Notifier>();

        // Application Services
        services.AddScoped<IEventPublisher, ResilientEventPublisher>();
        services.AddScoped<IEmailService, AwsSesEmailService>();

        // HttpContextAccessor para IUser
        services.AddHttpContextAccessor();
        services.AddScoped<IUser, AspNetUser>();

        // AWS Clients (credenciais via variáveis de ambiente)
        var awsConfig = configuration.GetSection("AWS");

        // Amazon SQS Client
        services.AddAWSService<IAmazonSQS>();

        // Amazon SES Client
        services.AddAWSService<IAmazonSimpleEmailService>();

        // Keycloak HttpClient com Polly e BaseAddress configurado
        var keycloakBaseUrl = configuration["KeycloakConfiguration:BaseUrl"] ?? "http://keycloak-service:8080";
        services.AddHttpClient<IKeycloakService, KeycloakService>(client =>
        {
            client.BaseAddress = new Uri(keycloakBaseUrl);
        }).AddStandardResilienceHandler();

        // Configurações
        services.Configure<KeycloakConfiguration>(
            configuration.GetSection("KeycloakConfiguration")
        );

        // OutboxDbContext
        services.AddDbContext<OutboxDbContext>(options =>
        {
            var connectionString = configuration.GetConnectionString("OutboxDb");

            if (!string.IsNullOrEmpty(connectionString))
            {
                options.UseNpgsql(connectionString);
            }
            else
            {
                options.UseInMemoryDatabase("OutboxDb");
            }
        });

        // Background job para processar outbox
        services.AddHostedService<OutboxProcessorJob>();

        // Auto-migrate OutboxDb at startup
        services.AddHostedService<OutboxDbMigrationService>();

        // MassTransit + Amazon SQS
        services.AddMassTransit(x =>
        {
            x.UsingAmazonSqs(
                (context, cfg) =>
                {
                    var region = awsConfig.GetValue<string>("Region") ?? "us-east-1";

                    cfg.Host(
                        region,
                        h =>
                        {
                            // Credenciais configuram via variáveis de ambiente:
                            // - AWS_ACCESS_KEY_ID
                            // - AWS_SECRET_ACCESS_KEY
                        }
                    );

                    // Retry policy com exponential backoff
                    cfg.UseMessageRetry(retry =>
                    {
                        retry.Exponential(
                            retryLimit: 5,
                            minInterval: TimeSpan.FromSeconds(2),
                            maxInterval: TimeSpan.FromMinutes(5),
                            intervalDelta: TimeSpan.FromSeconds(2)
                        );
                        retry.Ignore<ArgumentNullException>();
                        retry.Ignore<InvalidOperationException>();
                    });

                    // Configurar filas SQS
                    cfg.ConfigureEndpoints(context);
                }
            );
        });
    }
}
