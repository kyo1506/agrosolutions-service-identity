using System.Net;
using AgroSolutions.Identity.Api.Controllers;
using AgroSolutions.Identity.Domain.Interfaces;
using AgroSolutions.Identity.Shared.Constants;
using AgroSolutions.Identity.Shared.Models.Requests;
using AgroSolutions.Identity.Shared.Models.Responses;
using Microsoft.AspNetCore.Mvc;

namespace AgroSolutions.Identity.Api.V1.Controllers;

[ApiVersion("1.0")]
[Route("v{version:apiVersion}")]
[ApiController]
public class ValidationController(
    INotifier notifier,
    IUser appUser,
    IHttpContextAccessor httpContextAccessor,
    IWebHostEnvironment webHostEnvironment,
    IKeycloakService keycloakService,
    ILogger<ValidationController> logger
) : MainController(notifier, appUser, httpContextAccessor, webHostEnvironment)
{
    private readonly ILogger<ValidationController> _logger = logger;

    /// <summary>
    /// Validates a JWT token for other microservices.
    /// </summary>
    /// <remarks>
    /// This endpoint is used internally by other microservices to validate tokens.
    /// Returns user information if the token is valid.
    /// </remarks>
    [HttpPost("validate-token")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(Root<TokenValidationResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(Root<object>), StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<Root<TokenValidationResponse>>> ValidateToken()
    {
        var authHeader = Request.Headers.Authorization.FirstOrDefault();

        if (string.IsNullOrEmpty(authHeader) || !authHeader.StartsWith("Bearer "))
        {
            _logger.LogWarning("Token validation failed: Token not provided or invalid format");
            NotifyError("Token not provided or invalid format.");
            return CustomResponse<TokenValidationResponse>(statusCode: HttpStatusCode.Unauthorized);
        }

        var token = authHeader.Replace("Bearer ", "");

        try
        {
            var userInfo = await keycloakService.ValidateTokenAsync(token);

            if (userInfo == null)
            {
                _logger.LogWarning("Token validation failed: Invalid or expired token");
                NotifyError("Invalid or expired token.");
                return CustomResponse<TokenValidationResponse>(
                    statusCode: HttpStatusCode.Unauthorized
                );
            }

            _logger.LogInformation(
                "Token validated successfully for user {Username} ({UserId})",
                userInfo.Username,
                userInfo.Id
            );

            var response = new TokenValidationResponse
            {
                IsValid = true,
                UserId = userInfo.Id,
                Username = userInfo.Username,
                Email = userInfo.Email,
                FirstName = userInfo.FirstName,
                LastName = userInfo.LastName,
                ExpiresAt = userInfo.ExpiresAt,
                Roles = userInfo.Roles,
            };

            return CustomResponse(response);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating token");
            NotifyError("Error validating token.");
            return CustomResponse<TokenValidationResponse>(statusCode: HttpStatusCode.Unauthorized);
        }
    }

    /// <summary>
    /// Validates a user's permission for a specific resource and action.
    /// </summary>
    /// <remarks>
    /// This endpoint is used by other microservices to check if a user has the required permissions
    /// for accessing specific resources or performing certain actions.
    /// </remarks>
    [HttpPost("validate-permission")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(Root<PermissionValidationResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(Root<object>), StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<Root<PermissionValidationResponse>>> ValidatePermission(
        [FromBody] PermissionValidationRequest request
    )
    {
        if (request == null)
        {
            _logger.LogWarning("Permission validation failed: Request is null");
            NotifyError("Request cannot be null.");
            return CustomResponse<PermissionValidationResponse>(
                statusCode: HttpStatusCode.BadRequest
            );
        }

        var authHeader = Request.Headers.Authorization.FirstOrDefault();

        if (string.IsNullOrEmpty(authHeader) || !authHeader.StartsWith("Bearer "))
        {
            _logger.LogWarning(
                "Permission validation failed for {Resource}:{Action} - Token not provided",
                request.Resource,
                request.Action
            );
            NotifyError("Token not provided or invalid format.");
            return CustomResponse<PermissionValidationResponse>(
                statusCode: HttpStatusCode.Unauthorized
            );
        }

        var token = authHeader.Replace("Bearer ", "");

        try
        {
            var userInfo = await keycloakService.ValidateTokenAsync(token);

            if (userInfo == null)
            {
                _logger.LogWarning(
                    "Permission validation failed for {Resource}:{Action} - Invalid token",
                    request.Resource,
                    request.Action
                );
                NotifyError("Invalid or expired token.");
                return CustomResponse<PermissionValidationResponse>(
                    statusCode: HttpStatusCode.Unauthorized
                );
            }

            var hasPermission = await ValidateUserPermission(
                userInfo,
                request.Resource,
                request.Action
            );

            _logger.LogInformation(
                "Permission validation for user {Username} ({UserId}) on {Resource}:{Action} - Result: {HasPermission}",
                userInfo.Username,
                userInfo.Id,
                request.Resource,
                request.Action,
                hasPermission
            );

            var response = new PermissionValidationResponse
            {
                HasPermission = hasPermission,
                UserId = userInfo.Id,
                Resource = request.Resource,
                Action = request.Action,
            };

            return CustomResponse(response);
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Error validating permission for {Resource}:{Action}",
                request.Resource,
                request.Action
            );
            NotifyError("Error validating permission.");
            return CustomResponse<PermissionValidationResponse>(
                statusCode: HttpStatusCode.Unauthorized
            );
        }
    }

    #region Private Methods

    /// <summary>
    /// Valida se um usuário tem permissão para executar uma ação específica em um recurso.
    /// Sistema simplificado com apenas 3 permissões: users:manage, users:read e profiles:manage
    /// </summary>
    /// <param name="userInfo">Informações do usuário incluindo roles</param>
    /// <param name="resource">Recurso alvo (ex: "users", "profile")</param>
    /// <param name="action">Ação desejada (ex: "read", "manage")</param>
    /// <returns>True se o usuário tem a permissão, False caso contrário</returns>
    private static Task<bool> ValidateUserPermission(
        UserResponse userInfo,
        string resource,
        string action
    )
    {
        // Obtém as roles do usuário vindas do Keycloak
        var userRoles = userInfo.Roles ?? [];

        // Matriz de permissões por role - Sistema simplificado com apenas 3 permissões
        var rolePermissions = new Dictionary<string, List<string>>
        {
            ["admin"] =
            [
                Permissions.Users.Read,
                Permissions.Users.Manage,
                Permissions.Profile.Manage,
            ],
            ["user"] = [Permissions.Profile.Manage],
        };

        // Check for exact permission match
        var requiredPermission = $"{resource}:{action}";

        foreach (var role in userRoles)
        {
            var normalizedRole = role.ToLowerInvariant().Replace("role_", "");

            if (rolePermissions.ContainsKey(normalizedRole))
            {
                if (rolePermissions[normalizedRole].Contains(requiredPermission))
                {
                    return Task.FromResult(true);
                }
            }
        }

        return Task.FromResult(false);
    }

    #endregion
}
