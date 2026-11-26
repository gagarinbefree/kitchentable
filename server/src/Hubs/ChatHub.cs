using KitchenTable.Application;
using KitchenTable.Domain;
using MediatR;
using Microsoft.AspNetCore.SignalR;

namespace KitchenTable.Hubs;

public sealed class ChatHub(ISender mediator) : Hub
{
    public async Task<long> SendMessage(Guid sender, Guid token, string? body)
    {
        long id;
        try
        {
            id = await mediator.Send(new SendMessage(sender, token, body), Context.ConnectionAborted);
        }
        catch (MessageRuleException error) { throw new HubException(error.Message, error); }
        // Include retries: a committed write may have lost its original notification.
        await Clients.All.SendAsync("MessagesAvailable");
        return id;
    }

    public Task<List<Message>> History(long after) =>
        mediator.Send(new ReadHistory(after), Context.ConnectionAborted);
}
