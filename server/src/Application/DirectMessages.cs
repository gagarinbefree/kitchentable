using KitchenTable.Domain;
using MediatR;

namespace KitchenTable.Application;

public sealed record DirectRow(long Id, long Sender, long Recipient, string Body, DateTimeOffset SentAt);
public sealed record SendDirect(long Sender, long Recipient, Guid Token, string? Text) : IRequest<long>;
public sealed record ReadInbox(long Owner, long After) : IRequest<List<DirectRow>>;

public interface IDirectStore
{
    Task<long> Append(PersonalMessage message, CancellationToken ct);
    Task<List<DirectRow>> Inbox(long owner, long after, CancellationToken ct);
}

public sealed class SendDirectHandler(IDirectStore store) : IRequestHandler<SendDirect, long>
{
    public Task<long> Handle(SendDirect request, CancellationToken ct) =>
        store.Append(PersonalMessage.Create(request.Sender, request.Recipient, request.Token, request.Text), ct);
}

public sealed class ReadInboxHandler(IDirectStore store) : IRequestHandler<ReadInbox, List<DirectRow>>
{
    public Task<List<DirectRow>> Handle(ReadInbox request, CancellationToken ct) =>
        request.After < 0 ? throw new MessageRuleException("Invalid cursor.") : store.Inbox(request.Owner, request.After, ct);
}
