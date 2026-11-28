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
    public async Task Former_public_hub_is_unavailable()
    {
        var direct = new Uri(Environment.GetEnvironmentVariable("CHAT_TEST_URL")!);
        using var http = new HttpClient { BaseAddress = direct };
        using var response = await http.PostAsync("/chat/negotiate?negotiateVersion=1", null);
        Assert.Equal(System.Net.HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact, Trait("Category", "Live")]
    public async Task Replaced_QR_is_invalid_and_only_one_concurrent_scanner_can_claim_its_replacement()
    {
        var url = Environment.GetEnvironmentVariable("CHAT_TEST_URL")!;
        using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        var ct = limit.Token;
        await using var owner = Connect(url, Secret());
        await using var first = Connect(url, Secret());
        await using var second = Connect(url, Secret());
        await Task.WhenAll(owner.StartAsync(ct), first.StartAsync(ct), second.StartAsync(ct));
        var old = await owner.InvokeAsync<string>("CreateInvite", ct);
        var current = await owner.InvokeAsync<string>("CreateInvite", ct);
        await Assert.ThrowsAsync<HubException>(() => first.InvokeAsync<long>("AcceptInvite", old, ct));
        async Task<bool> TryClaim(HubConnection scanner)
        {
            try { await scanner.InvokeAsync<long>("AcceptInvite", current, ct); return true; }
            catch (HubException) { return false; }
        }
        var claims = await Task.WhenAll(TryClaim(first), TryClaim(second));
        Assert.Single(claims, accepted => accepted);
        var winner = claims[0] ? first : second;
        var loser = claims[0] ? second : first;
        var winnerNumber = await winner.InvokeAsync<long>("MyNumber", ct);
        Assert.Equal(new[] { winnerNumber }, await owner.InvokeAsync<long[]>("Contacts", ct));
        Assert.Empty(await loser.InvokeAsync<long[]>("Contacts", ct));
    }

    [Fact, Trait("Category", "Live")]
    public async Task Direct_messages_and_notifications_are_visible_only_to_the_two_participants()
    {
        var directUrl = Environment.GetEnvironmentVariable("CHAT_TEST_URL")!;
        using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(50));
        var ct = limit.Token;
        var secret = Secret();
        await using var a = Connect(directUrl, secret);
        await using var b = Connect(directUrl, Secret());
        await using var c = Connect(directUrl, Secret());
        var received = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var leaked = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        b.On("MessagesAvailable", () => received.TrySetResult());
        c.On("MessagesAvailable", () => leaked.TrySetResult());
        await Task.WhenAll(a.StartAsync(ct), b.StartAsync(ct), c.StartAsync(ct));
        var alice = await a.InvokeAsync<long>("MyNumber", ct);
        var bob = await b.InvokeAsync<long>("MyNumber", ct);
        Assert.NotEqual(alice, bob);
        Assert.Empty(await a.InvokeAsync<long[]>("Contacts", ct));
        Assert.Empty(await b.InvokeAsync<long[]>("Contacts", ct));
        await Assert.ThrowsAsync<HubException>(() => a.InvokeAsync<long>("SendTo", bob, Guid.NewGuid(), "before QR", ct));
        var aliceChanged = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var bobChanged = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        a.On("ContactsChanged", () => aliceChanged.TrySetResult());
        b.On("ContactsChanged", () => bobChanged.TrySetResult());
        c.On("ContactsChanged", () => leaked.TrySetResult());
        var tokenQr = await a.InvokeAsync<string>("CreateInvite", ct);
        Assert.Equal(alice, await b.InvokeAsync<long>("PreviewInvite", tokenQr, ct));
        await Assert.ThrowsAsync<HubException>(() => a.InvokeAsync<long>("AcceptInvite", tokenQr, ct));
        await Assert.ThrowsAsync<HubException>(() => b.InvokeAsync<long>("AcceptInvite", alice.ToString(), ct));
        Assert.Empty(await b.InvokeAsync<long[]>("Contacts", ct));
        Assert.Equal(alice, await b.InvokeAsync<long>("AcceptInvite", tokenQr, ct));
        await Task.WhenAll(aliceChanged.Task, bobChanged.Task).WaitAsync(ct);
        Assert.Equal(new[] { bob }, await a.InvokeAsync<long[]>("Contacts", ct));
        Assert.Equal(new[] { alice }, await b.InvokeAsync<long[]>("Contacts", ct));
        Assert.Empty(await b.InvokeAsync<Row[]>("History", 0L, ct));
        Assert.Equal(alice, await b.InvokeAsync<long>("AcceptInvite", tokenQr, ct));
        await Assert.ThrowsAsync<HubException>(() => c.InvokeAsync<long>("AcceptInvite", tokenQr, ct));
        Assert.Empty(await c.InvokeAsync<long[]>("Contacts", ct));
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
        Assert.False(leaked.Task.IsCompleted);
        await using var anonymous = new HubConnectionBuilder().WithUrl(directUrl).Build();
        var rejected = await Assert.ThrowsAsync<HttpRequestException>(() => anonymous.StartAsync(ct));
        Assert.Equal(System.Net.HttpStatusCode.Unauthorized, rejected.StatusCode);
    }
}
