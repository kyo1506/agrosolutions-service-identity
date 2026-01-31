using AgroSolutions.Identity.Shared.Models.Requests;
using AgroSolutions.Identity.Shared.Models.Responses;

namespace AgroSolutions.Identity.Domain.Interfaces;

public interface IKeycloakService
{
    Task<TokenResponse?> LoginAsync(LoginRequest request);
    Task<UserResponse?> CreateUserAsync(CreateUserRequest request);
    Task<IEnumerable<UserResponse>?> GetUsersAsync();
    Task<UserResponse?> GetUserByIdAsync(Guid id);
    Task<UpdateUserResponse?> UpdateUserAsync(Guid id, UpdateUserRequest request);
    Task<bool> DeleteUserAsync(Guid id);

    /// <summary>
    /// Valida um token JWT e retorna informações do usuário se válido.
    /// </summary>
    /// <param name="token">Token JWT a ser validado</param>
    /// <returns>Informações do usuário se o token for válido, caso contrário null</returns>
    Task<UserResponse?> ValidateTokenAsync(string token);
}
