using KitchenTable.Application;
using KitchenTable.Hubs;
using KitchenTable.Infrastructure;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.SignalR;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);
var connection = builder.Configuration.GetConnectionString("Chat")
    ?? throw new InvalidOperationException("Set ConnectionStrings__Chat.");
builder.Services.AddSingleton(_ => NpgsqlDataSource.Create(connection));
builder.Services.AddSingleton<PostgresMessages>();
builder.Services.AddSingleton<PostgresDirectMessages>();
builder.Services.AddSingleton<IDirectStore>(sp => sp.GetRequiredService<PostgresDirectMessages>());
builder.Services.AddAuthentication(SubscriberAuthentication.Method)
    .AddScheme<Microsoft.AspNetCore.Authentication.AuthenticationSchemeOptions, SubscriberAuthentication>(
        SubscriberAuthentication.Method, _ => { });
builder.Services.AddAuthorization();
builder.Services.AddSingleton<IMessageStore>(sp => sp.GetRequiredService<PostgresMessages>());
builder.Services.AddMediatR(options => options.RegisterServicesFromAssemblyContaining<SendMessage>());
builder.Services.AddSignalR(options => { options.MaximumReceiveMessageSize = 65536; options.AddFilter<HawkHubFilter>(); });
builder.Services.AddHttpClient("hawk", http => http.Timeout = TimeSpan.FromSeconds(3));
builder.Services.AddSingleton<HawkReporter>();
builder.Services.AddRateLimiter(options => options.AddFixedWindowLimiter("diagnostics", limiter =>
{
    limiter.PermitLimit = 20;
    limiter.Window = TimeSpan.FromMinutes(1);
}));
var app = builder.Build();
await app.Services.GetRequiredService<PostgresMessages>().Initialize(app.Lifetime.ApplicationStopping);
await app.Services.GetRequiredService<PostgresDirectMessages>().Initialize(app.Lifetime.ApplicationStopping);
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
app.MapHub<DirectHub>("/direct").RequireAuthorization();
app.MapHub<ChatHub>("/chat");
app.MapGet("/health", () => Results.Ok());
app.MapPost("/diagnostics/{code}", async (string code, HawkReporter reporter) =>
{
    if (code is not ("flutter-error" or "platform-error" or "send-failed")) return Results.BadRequest();
    await reporter.Report("flutter", code);
    return Results.NoContent();
}).RequireRateLimiting("diagnostics");
await app.RunAsync();
