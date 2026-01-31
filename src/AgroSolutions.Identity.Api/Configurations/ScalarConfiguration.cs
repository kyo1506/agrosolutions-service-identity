using Scalar.AspNetCore;

namespace AgroSolutions.Identity.Api.Configurations;

public static class ScalarConfig
{
    public static void AddScalarConfiguration(this IServiceCollection services)
    {
        services.AddOpenApi();
    }

    public static void UseScalarConfig(this IApplicationBuilder app)
    {
        if (app is WebApplication webApp)
        {
            webApp.MapOpenApi();
            webApp.MapScalarApiReference(options =>
            {
                options
                    .WithTitle("AgroSolutions Identity Service API")
                    .WithTheme(ScalarTheme.Moon)
                    .WithDefaultHttpClient(ScalarTarget.CSharp, ScalarClient.HttpClient);
            });
        }
    }
}
