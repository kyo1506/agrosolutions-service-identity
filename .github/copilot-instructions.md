# AgroSolutions Identity Service - AI Coding Agent Instructions

## Architecture Overview

This is an **ASP.NET Core Web API (.NET 10.0)** that serves as an authentication and identity management service wrapping **Keycloak 26.0.5** as the identity provider. The architecture follows clean architecture principles with clear separation of concerns:

- **Api**: Controllers, middleware, configurations, and ASP.NET Core setup ([Program.cs](../src/AgroSolutions.Identity.Api/Program.cs))
- **Domain**: Core business interfaces ([IKeycloakService](../src/AgroSolutions.Identity.Domain/Interfaces/IKeycloakService.cs), [INotifier](../src/AgroSolutions.Identity.Domain/Interfaces/INotifier.cs), [IUser](../src/AgroSolutions.Identity.Domain/Interfaces/IUser.cs)) and notification pattern
- **Infrastructure**: Keycloak integration ([KeycloakService](../src/AgroSolutions.Identity.Infrastructure/Services/KeycloakService.cs))
- **Shared**: DTOs, constants, mappers, validators (shared across layers)
- **Test**: Unit tests using xUnit and Moq

## Critical Patterns

### Response Wrapper Pattern
All API responses use `Root<T>` wrapper ([Root.cs](../src/AgroSolutions.Identity.Shared/Models/Generics/Root.cs)):
```csharp
public class Root<T> {
    public int StatusCode { get; set; }
    public bool Success { get; set; }
    public T? Data { get; set; }
    public IEnumerable<string>? Errors { get; set; }
}
```
Controllers inherit from [MainController](../src/AgroSolutions.Identity.Api/Controllers/MainController.cs) which provides `CustomResponse<T>()` methods.

### Notification Pattern for Domain Validation
Use `INotifier` ([Notifier.cs](../src/AgroSolutions.Identity.Domain/Notifications/Notifier.cs)) to collect validation errors rather than throwing exceptions:
```csharp
notifier.Handle(new Notification("Error message"));
return CustomResponse<T>(statusCode: HttpStatusCode.BadRequest);
```
Check `notifier.HasNotification()` before returning success responses.

### Permission-Based Authorization
The system uses **JWT scope-based permissions** ([Permissions.cs](../src/AgroSolutions.Identity.Shared/Constants/Permissions.cs)). Three core permissions:
- `users:read` - Read user information
- `users:manage` - Full user management
- `profiles:manage` - Profile management

Authorization policies are configured in [IdentityConfiguration.cs](../src/AgroSolutions.Identity.Api/Configurations/IdentityConfiguration.cs) using scope assertions from JWT tokens issued by Keycloak.

### Keycloak Integration
[KeycloakService](../src/AgroSolutions.Identity.Infrastructure/Services/KeycloakService.cs) uses:
- **Admin token caching** (static `_adminAccessToken` with expiration check)
- **HttpClient with Polly resilience policies** configured in [DependencyInjectionConfiguration.cs](../src/AgroSolutions.Identity.Api/Configurations/DependencyInjectionConfiguration.cs)
- **Dual issuer validation** (supports both `localhost:8080` and `keycloak:8080` in [IdentityConfiguration.cs](../src/AgroSolutions.Identity.Api/Configurations/IdentityConfiguration.cs#L39-L43))

## Resilience & Observability

### Polly Policies
[ResilienceConfiguration.cs](../src/AgroSolutions.Identity.Api/Configurations/ResilienceConfiguration.cs) implements:
- Circuit Breaker (5 failures, 30s break)
- Retry with exponential backoff (3 attempts)
- Timeout (30s)
- Bulkhead (10 parallel, 20 queued)

### OpenTelemetry Stack
Full observability configured in [OpenTelemetryConfiguration.cs](../src/AgroSolutions.Identity.Api/Configurations/OpenTelemetryConfiguration.cs):
- Traces → Tempo (OTLP via otel-collector)
- Logs → Loki (via Serilog OpenTelemetry sink)
- Metrics → Prometheus

[LogContextMiddleware](../src/AgroSolutions.Identity.Api/Middlewares/LogContextMiddleware.cs) enriches logs with:
- RequestId, CorrelationId (Kong-aware)
- UserId, Username, SessionId (from JWT)

## Development Workflows

### Local Development with Docker Compose
```bash
docker-compose up -d  # Starts Keycloak, Postgres, observability stack
```
Access points:
- Identity API: http://localhost:5001
- Keycloak Admin: http://localhost:8080 (admin/admin)
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090

### Configuration
Environment-specific: `appsettings.{Environment}.json`
Required Keycloak settings ([appsettings.json](../src/AgroSolutions.Identity.Api/appsettings.json)):
```json
"KeycloakConfiguration": {
  "BaseUrl": "http://keycloak:8080",
  "TargetRealm": "agrosolutions",
  "AdminClientId": "agrosolutions-api-service-account",
  "ApiClientId": "agrosolutions-api"
}
```

### Running Tests
```bash
dotnet test src/AgroSolutions.Identity.Test/AgroSolutions.Identity.Test.csproj
```
Tests use Moq for dependencies. See [AuthTest.cs](../src/AgroSolutions.Identity.Test/AuthTest.cs) for controller test patterns.

### Building & Running
```bash
dotnet restore
dotnet build
dotnet run --project src/AgroSolutions.Identity.Api
```
Docker build uses multi-stage Alpine images ([Dockerfile](../Dockerfile)).

## Conventions

- **API Versioning**: URL-based (`/v1/...`), configured in [ApiConfiguration.cs](../src/AgroSolutions.Identity.Api/Configurations/ApiConfiguration.cs)
- **Localization**: Supports `pt-BR` (default) and `en-US` ([Program.cs](../src/AgroSolutions.Identity.Api/Program.cs#L26-L33))
- **Global Exception Handling**: [GlobalExceptionHandler](../src/AgroSolutions.Identity.Api/Extensions/GlobalExceptionHandler.cs) catches unhandled exceptions
- **Health Checks**: Configured via [HealthChecksConfiguration.cs](../src/AgroSolutions.Identity.Api/Configurations/HealthChecksConfiguration.cs)
- **API Documentation**: Scalar (replacement for Swagger) at `/scalar/v1`

## Key Integration Points

- **Keycloak Admin API**: User CRUD operations require admin client credentials
- **Keycloak Token Endpoint**: User login uses Resource Owner Password flow with API client
- **OpenTelemetry Collector**: Centralized telemetry export (port 4317/4318)
- **JWT Validation**: ASP.NET Core middleware validates tokens via Keycloak's `.well-known/openid-configuration`

## Common Tasks

**Adding a new endpoint**: Create controller in `V1/Controllers/`, inherit from `MainController`, use `CustomResponse<T>()` for consistency.

**Adding a new permission**: Define in [Permissions.cs](../src/AgroSolutions.Identity.Shared/Constants/Permissions.cs), add policy in [IdentityConfiguration.cs](../src/AgroSolutions.Identity.Api/Configurations/IdentityConfiguration.cs), register in [AppAuthorizationPolicies.cs](../src/AgroSolutions.Identity.Api/Extensions/AppAuthorizationPolicies.cs).

**Domain validation**: Use `INotifier` in services, check in controllers with `CustomResponse<T>()` which automatically handles error responses.
