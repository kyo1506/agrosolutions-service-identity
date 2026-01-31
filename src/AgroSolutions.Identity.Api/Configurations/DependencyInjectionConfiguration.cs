using AgroSolutions.Identity.Api.Extensions;
using AgroSolutions.Identity.Domain.Interfaces;
using AgroSolutions.Identity.Domain.Notifications;
using AgroSolutions.Identity.Infrastructure.Extensions;
using AgroSolutions.Identity.Infrastructure.Services;
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

        services.AddExceptionHandler<GlobalExceptionHandler>();

        services.AddProblemDetails();
    }
}
