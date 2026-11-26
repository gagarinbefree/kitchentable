using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using KitchenTable.Domain;

namespace KitchenTable.Infrastructure;

public sealed class HawkReporter(IConfiguration config, IHttpClientFactory clients, ILogger<HawkReporter> log)
{
    public async Task Report(string kind, string title)
    {
        var token = config["Hawk:Token"];
        if (string.IsNullOrEmpty(token)) return;
        try
        {
            using var credentials = JsonDocument.Parse(Convert.FromBase64String(token));
            var project = credentials.RootElement.GetProperty("integrationId").GetGuid();
            using var http = clients.CreateClient("hawk");
            var collector = new Uri($"https://{project:D}.k1.hawk.so/");
            using var response = await http.PostAsJsonAsync(collector, new {
                token, catcherType = $"error/{kind}", payload = new { title, type = title }
            });
            if (!response.IsSuccessStatusCode)
                log.LogWarning("Hawk returned HTTP {Status}", (int)response.StatusCode);
        }
        catch (Exception error) when (error is HttpRequestException or OperationCanceledException or
            JsonException or FormatException or KeyNotFoundException or InvalidOperationException)
        {
            log.LogWarning("Hawk delivery failed ({Type})", error.GetType().Name);
        }
    }
}

public sealed class HawkHubFilter(HawkReporter reporter) : IHubFilter
{
    public async ValueTask<object?> InvokeMethodAsync(HubInvocationContext context,
        Func<HubInvocationContext, ValueTask<object?>> next)
    {
        try { return await next(context); }
        catch (Exception error) when (error is not (HubException or MessageRuleException or OperationCanceledException))
        {
            await reporter.Report("dotnet", error.GetType().Name);
            throw;
        }
    }
}
