using System.ComponentModel.DataAnnotations;

namespace AgroSolutions.Identity.Shared.Models.Requests;

public class RefreshTokenRequest
{
    [Required]
    public string? RefreshToken { get; set; }
}
