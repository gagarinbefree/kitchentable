using System.Globalization;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace KitchenTable.Infrastructure;

public sealed class SubscriberAuthentication(IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger, UrlEncoder encoder, PostgresDirectMessages subscribers)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string Method = "SubscriberKey";

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (!Request.Path.StartsWithSegments("/direct") || string.IsNullOrEmpty(header))
            return AuthenticateResult.NoResult();
        if (header.Length != 71 || !header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return AuthenticateResult.Fail("Invalid device credential.");
        byte[] key;
        try { key = Convert.FromHexString(header.AsSpan(7)); }
        catch (FormatException) { return AuthenticateResult.Fail("Invalid device credential."); }
        var number = await subscribers.Identify(SHA256.HashData(key), Context.RequestAborted);
        var claim = new Claim(ClaimTypes.NameIdentifier, number.ToString(CultureInfo.InvariantCulture));
        var principal = new ClaimsPrincipal(new ClaimsIdentity([claim], Method));
        return AuthenticateResult.Success(new AuthenticationTicket(principal, Method));
    }
}
