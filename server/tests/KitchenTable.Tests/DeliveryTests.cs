using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.AspNetCore.SignalR;
using Xunit;

namespace KitchenTable.Tests;

[Collection("Live SignalR")]
public class DeliveryTests
{
    private record Row(long Id, Guid Sender, string Body, DateTimeOffset SentAt);

    [Fact, Trait("Category", "Live")]
    public async Task Peers_receive_committed_messages_and_catch_up_without_duplicates()
    {
        var url = Environment.GetEnvironmentVariable("CHAT_TEST_URL")
            ?? throw new InvalidOperationException("Set CHAT_TEST_URL to an isolated test hub");
        using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(45));
        var ct = limit.Token;
        await using var a = new HubConnectionBuilder().WithUrl(url).Build();
        await using var b = new HubConnectionBuilder().WithUrl(url).Build();
        var notice = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        b.On("MessagesAvailable", () => notice.TrySetResult());
        await Task.WhenAll(a.StartAsync(ct), b.StartAsync(ct));
        var author = Guid.NewGuid();
        var token = Guid.NewGuid();
        var id = await a.InvokeAsync<long>("SendMessage", author, token, "Привет 👋", ct);
        await notice.Task.WaitAsync(ct);
        var page = await b.InvokeAsync<Row[]>("History", id - 1, ct);
        Assert.Contains(page, row => row.Id == id && row.Sender == author && row.Body == "Привет 👋");
        var retries = await Task.WhenAll(
            a.InvokeAsync<long>("SendMessage", author, token, "Привет 👋", ct),
            b.InvokeAsync<long>("SendMessage", author, token, "Привет 👋", ct));
        Assert.All(retries, retryId => Assert.Equal(id, retryId));
        await Assert.ThrowsAsync<HubException>(() =>
            a.InvokeAsync<long>("SendMessage", author, token, "Другой текст", ct));
        await b.StopAsync(ct);
        var second = await a.InvokeAsync<long>("SendMessage", author, Guid.NewGuid(), "До связи", ct);
        await b.StartAsync(ct);
        var missed = await b.InvokeAsync<Row[]>("History", id, ct);
        Assert.Contains(missed, row => row.Id == second);
        Assert.DoesNotContain(missed, row => row.Id <= id);
    }
}
