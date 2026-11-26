using System.Globalization;
using KitchenTable.Application;
using KitchenTable.Domain;
using MediatR;
using Microsoft.AspNetCore.SignalR;

namespace KitchenTable.Hubs;

public sealed class DirectHub(ISender mediator) : Hub
{
    public long MyNumber() => long.Parse(Context.UserIdentifier!, CultureInfo.InvariantCulture);

    public Task<List<long>> Contacts() => mediator.Send(new ListContacts(MyNumber()), Context.ConnectionAborted);
    public Task<string> CreateInvite() => mediator.Send(new CreateContactInvite(MyNumber()), Context.ConnectionAborted);

    public Task<long> PreviewInvite(string token) => Resolve(new PreviewContactInvite(MyNumber(), token));

    public async Task<long> AcceptInvite(string token)
    {
        var owner = await Resolve(new AcceptContactInvite(MyNumber(), token));
        await Clients.Users(Context.UserIdentifier!, owner.ToString(CultureInfo.InvariantCulture)).SendAsync("ContactsChanged");
        return owner;
    }

    private async Task<long> Resolve(IRequest<long> request)
    {
        try { return await mediator.Send(request, Context.ConnectionAborted); }
        catch (MessageRuleException error) { throw new HubException(error.Message, error); }
    }

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
