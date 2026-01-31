using AgroSolutions.Identity.Api.Extensions;
using AgroSolutions.Identity.Domain.Interfaces;
using AgroSolutions.Identity.Domain.Notifications;
using AgroSolutions.Identity.Infrastructure.BackgroundJobs;
using AgroSolutions.Identity.Infrastructure.Data;
using AgroSolutions.Identity.Infrastructure.Extensions;
using AgroSolutions.Identity.Infrastructure.Messaging;
using AgroSolutions.Identity.Infrastructure.Services;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace AgroSolutions.Identity.Api.Configurations;

public static class DependencyInjectionConfiguration
{
    public static void ResolveDependencies(this IServiceCollection services)
    {
        services.AddScoped<INotifier, Notifier>();

        services.AddSingleton<IHttpContextAccessor, HttpContextAccessor>();

        services.AddScoped<IUser, AspNetUser>();

        services.Configure<KeycloakConfiguration>(
            services
                .BuildServiceProvider()
                .GetRequiredService<IConfiguration>()
                .GetSection(nameof(KeycloakConfiguration))
        );

        services
            .AddHttpClient<IKeycloakService, KeycloakService>(
                (serviceProvider, client) =>
                {
                    var config = serviceProvider
                        .GetRequiredService<IOptions<KeycloakConfiguration>>()
                        .Value;
                    client.BaseAddress = new Uri(config.BaseUrl);
                    client.Timeout = TimeSpan.FromSeconds(60);
                }
            )
            .AddPolicyHandler(
                (serviceProvider, request) =>
                {
                    var logger = serviceProvider
                        .GetRequiredService<ILoggerFactory>()
                        .CreateLogger("Polly.Resilience");
                    return ResilienceConfiguration.GetCombinedPolicy(logger);
                }
            );

        // OutboxDbContext - in-memory para desenvolvimento, use SQL em produção
        services.AddDbContext<OutboxDbContext>(options =>
        {
            var connectionString = services
                .BuildServiceProvider()
                .GetRequiredService<IConfiguration>()
                .GetConnectionString("OutboxDb");

            if (!string.IsNullOrEmpty(connectionString))
            {
                options.UseNpgsql(connectionString);
            }
            else
            {
                // Fallback para in-memory em desenvolvimento
                options.UseInMemoryDatabase("OutboxDb");
            }
        });

        // Event Publisher with resilience and outbox
        services.AddScoped<IEventPublisher, ResilientEventPublisher>();

        // Background job para processar outbox
        services.AddHostedService<OutboxProcessorJob>();

        // MassTransit + RabbitMQ com retry policy e dead-letter queue
        services.AddMassTransit(x =>
        {
            x.UsingRabbitMq(
                (context, cfg) =>
                {
                    var rabbitMqSettings = context
                        .GetRequiredService<IConfiguration>()
                        .GetSection("RabbitMQ");

                    cfg.Host(
                        rabbitMqSettings["Host"],
                        "/",
                        h =>
                        {
                            h.Username(rabbitMqSettings["Username"] ?? "guest");
                            h.Password(rabbitMqSettings["Password"] ?? "guest");
                        }
                    );

                    // Configurar retry policy com exponential backoff
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

                    // Configurar dead-letter queue para mensagens falhadas
                    cfg.ReceiveEndpoint(
                        "identity-events-dlq",
                        e =>
                        {
                            e.ConfigureConsumeTopology = false;
                            e.Bind("identity-events-dead-letter-exchange");
                        }
                    );

                    cfg.ConfigureEndpoints(context);
                }
            );
        });

        services.AddExceptionHandler<GlobalExceptionHandler>();

        services.AddProblemDetails();
    }
}
