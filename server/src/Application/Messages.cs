using KitchenTable.Domain;
using MediatR;

namespace KitchenTable.Application;

public sealed record Message(long Id, Guid Sender, string Body, DateTimeOffset SentAt);
public sealed record SendMessage(Guid Sender, Guid Token, string? Body) : IRequest<long>;
public sealed record ReadHistory(long After) : IRequest<List<Message>>;
public interface IMessageStore
{
    Task<long> Append(DraftMessage message, CancellationToken ct);
    Task<List<Message>> ReadAfter(long after, CancellationToken ct);
}

public sealed class SendMessageHandler(IMessageStore store) : IRequestHandler<SendMessage, long>
{
    public Task<long> Handle(SendMessage request, CancellationToken ct) =>
        store.Append(DraftMessage.Create(request.Sender, request.Token, request.Body), ct);
}

public sealed class ReadHistoryHandler(IMessageStore store) : IRequestHandler<ReadHistory, List<Message>>
{
    public Task<List<Message>> Handle(ReadHistory request, CancellationToken ct) =>
        request.After < 0 ? throw new MessageRuleException("Invalid cursor.") : store.ReadAfter(request.After, ct);
}
