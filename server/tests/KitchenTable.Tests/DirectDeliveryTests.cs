using System.Security.Cryptography;
using Microsoft.AspNetCore.SignalR;
using Microsoft.AspNetCore.SignalR.Client;
using Xunit;

namespace KitchenTable.Tests;

[Collection("Live SignalR")]
public class DirectDeliveryTests
{
    private record Row(long Id, long Sender, long Recipient, string Body, DateTimeOffset SentAt);
    private static HubConnection Connect(string url, string secret) =>
        new HubConnectionBuilder().WithUrl(url, options =>
            options.Headers["Authorization"] = "Bearer " + secret).Build();
    private static string Secret() => Convert.ToHexString(RandomNumberGenerator.GetBytes(32));

    [Fact, Trait("Category", "Live")]
    public async Task Direct_messages_and_notifications_are_visible_only_to_the_two_participants()
    {
        var roomUrl = Environment.GetEnvironmentVariable("CHAT_TEST_URL")!;
        var directUrl = new Uri(new Uri(roomUrl), "/direct").ToString();
        using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(50));
        var ct = limit.Token;
        var secret = Secret();
        await using var a = Connect(directUrl, secret);
        await using var b = Connect(directUrl, Secret());
        await using var c = Connect(directUrl, Secret());
        await using var room = new HubConnectionBuilder().WithUrl(roomUrl).Build();
        var received = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var leaked = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        b.On("MessagesAvailable", () => received.TrySetResult());
        c.On("MessagesAvailable", () => leaked.TrySetResult());
        room.On("MessagesAvailable", () => leaked.TrySetResult());
        await Task.WhenAll(a.StartAsync(ct), b.StartAsync(ct), c.StartAsync(ct), room.StartAsync(ct));
        var alice = await a.InvokeAsync<long>("MyNumber", ct);
        var bob = await b.InvokeAsync<long>("MyNumber", ct);
        Assert.NotEqual(alice, bob);
        Assert.True(await a.InvokeAsync<bool>("SubscriberExists", bob, ct));
        var token = Guid.NewGuid();
        var body = $"Личное {token}";
        var id = await a.InvokeAsync<long>("SendTo", bob, token, body, ct);
        await received.Task.WaitAsync(ct);
        Assert.Equal(id, await a.InvokeAsync<long>("SendTo", bob, token, body, ct));
        await Assert.ThrowsAsync<HubException>(() => a.InvokeAsync<long>("SendTo", bob, token, "Changed", ct));
        await Assert.ThrowsAsync<HubException>(() => a.InvokeAsync<long>("SendTo", alice, Guid.NewGuid(), body, ct));
        await Assert.ThrowsAsync<HubException>(() => a.InvokeAsync<long>("SendTo", long.MaxValue, Guid.NewGuid(), body, ct));
        var rows = await b.InvokeAsync<Row[]>("History", 0L, ct);
        var row = Assert.Single(rows);
        Assert.Equal((id, alice, bob, body), (row.Id, row.Sender, row.Recipient, row.Body));
        await a.StopAsync(ct);
        var reply = await b.InvokeAsync<long>("SendTo", alice, Guid.NewGuid(), "Ответ", ct);
        await a.StartAsync(ct);
        Assert.Equal(alice, await a.InvokeAsync<long>("MyNumber", ct));
        var missed = Assert.Single(await a.InvokeAsync<Row[]>("History", id, ct));
        Assert.Equal((reply, bob, alice), (missed.Id, missed.Sender, missed.Recipient));
        Assert.Empty(await c.InvokeAsync<Row[]>("History", 0L, ct));
        var publicRows = await room.InvokeAsync<System.Text.Json.JsonElement[]>("History", 0L, ct);
        Assert.DoesNotContain(publicRows, m => m.GetProperty("body").GetString() == body);
        Assert.False(leaked.Task.IsCompleted);
        await using var anonymous = new HubConnectionBuilder().WithUrl(directUrl).Build();
        var rejected = await Assert.ThrowsAsync<HttpRequestException>(() => anonymous.StartAsync(ct));
        Assert.Equal(System.Net.HttpStatusCode.Unauthorized, rejected.StatusCode);
    }
}
