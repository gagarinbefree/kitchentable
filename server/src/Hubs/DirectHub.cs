using System.Globalization;
using KitchenTable.Application;
using KitchenTable.Domain;
using MediatR;
using Microsoft.AspNetCore.SignalR;

namespace KitchenTable.Hubs;

public sealed class DirectHub(ISender mediator) : Hub
{
    public long MyNumber() => long.Parse(Context.UserIdentifier!, CultureInfo.InvariantCulture);

    public Task<bool> SubscriberExists(long number) =>
        mediator.Send(new FindSubscriber(number), Context.ConnectionAborted);

    public Task<List<DirectRow>> History(long after) =>
        mediator.Send(new ReadInbox(MyNumber(), after), Context.ConnectionAborted);

    public async Task<long> SendTo(long recipient, Guid token, string? text)
    {
        var sender = MyNumber();
        long id;
        try { id = await mediator.Send(new SendDirect(sender, recipient, token, text), Context.ConnectionAborted); }
        catch (MessageRuleException error) { throw new HubException(error.Message, error); }
        await Clients.Users(Context.UserIdentifier!, recipient.ToString(CultureInfo.InvariantCulture)).SendAsync("MessagesAvailable");
        return id;
    }
}
