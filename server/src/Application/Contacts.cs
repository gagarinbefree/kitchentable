using System.Security.Cryptography;
using KitchenTable.Domain;
using MediatR;

namespace KitchenTable.Application;

public sealed record ListContacts(long Owner) : IRequest<List<long>>;
public sealed record CreateContactInvite(long Owner) : IRequest<string>;
public sealed record PreviewContactInvite(long Scanner, string Token) : IRequest<long>;
public sealed record AcceptContactInvite(long Scanner, string Token) : IRequest<long>;

public interface IContactStore
{
    Task<List<long>> List(long owner, CancellationToken ct);
    Task SaveInvite(long owner, byte[] digest, CancellationToken ct);
    Task<long> Preview(long scanner, byte[] digest, CancellationToken ct);
    Task<long> Accept(long scanner, byte[] digest, CancellationToken ct);
}

public sealed class ContactHandler(IContactStore store) :
    IRequestHandler<ListContacts, List<long>>, IRequestHandler<CreateContactInvite, string>,
    IRequestHandler<PreviewContactInvite, long>, IRequestHandler<AcceptContactInvite, long>
{
    public Task<List<long>> Handle(ListContacts request, CancellationToken ct) => store.List(request.Owner, ct);

    public async Task<string> Handle(CreateContactInvite request, CancellationToken ct)
    {
        var key = RandomNumberGenerator.GetBytes(32);
        await store.SaveInvite(request.Owner, SHA256.HashData(key), ct);
        return Convert.ToHexStringLower(key);
    }

    public Task<long> Handle(PreviewContactInvite request, CancellationToken ct) =>
        store.Preview(request.Scanner, Digest(request.Token), ct);

    public Task<long> Handle(AcceptContactInvite request, CancellationToken ct) =>
        store.Accept(request.Scanner, Digest(request.Token), ct);

    private static byte[] Digest(string? token)
    {
        if (token is not { Length: 64 } || !token.All(Uri.IsHexDigit))
            throw new MessageRuleException("Invalid QR invitation.");
        return SHA256.HashData(Convert.FromHexString(token));
    }
}
