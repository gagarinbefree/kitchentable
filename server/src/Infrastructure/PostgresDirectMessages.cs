using KitchenTable.Application;
using KitchenTable.Domain;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace KitchenTable.Infrastructure;

public sealed class PostgresDirectMessages(IDbContextFactory<ChatDbContext> contexts) : IDirectStore
{
    public async Task<long> Identify(byte[] keyHash, CancellationToken ct)
    {
        await using var db = await contexts.CreateDbContextAsync(ct);
        var numbers = db.Subscribers.Where(s => s.KeyHash == keyHash).Select(s => (long?)s.Number);
        if (await numbers.SingleOrDefaultAsync(ct) is long existing) return existing;
        var subscriber = new Subscriber { KeyHash = keyHash };
        db.Subscribers.Add(subscriber);
        try
        {
            await db.SaveChangesAsync(ct);
            return subscriber.Number;
        }
        catch (DbUpdateException e) when (e.InnerException is PostgresException
            { SqlState: PostgresErrorCodes.UniqueViolation, ConstraintName: "subscribers_key_hash_key" })
        {
            // A simultaneous connection registered this installation first.
            return (await numbers.SingleAsync(ct))!.Value;
        }
    }

    public async Task<long> Append(PersonalMessage message, CancellationToken ct)
    {
        await using var db = await contexts.CreateDbContextAsync(ct);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        // Hold the singleton row until commit so a later ID cannot overtake an uncommitted message.
        if (await db.MessageWriteGate.Where(g => g.Id == 1)
                .ExecuteUpdateAsync(s => s.SetProperty(g => g.Id, g => g.Id), ct) != 1)
            throw new InvalidOperationException("Missing message write gate.");

        var previous = await db.Messages.AsNoTracking()
            .SingleOrDefaultAsync(m => m.Sender == message.Sender && m.Token == message.Token, ct);
        if (previous != null)
        {
            if (previous.Recipient != message.Recipient || previous.Body != message.Body)
                throw new MessageRuleException("Conflicting message token.");
            return previous.Id;
        }

        var first = Math.Min(message.Sender, message.Recipient);
        var second = Math.Max(message.Sender, message.Recipient);
        var contact = db.Contacts.Where(c => c.FirstNumber == first && c.SecondNumber == second);
        if (!await contact.AnyAsync(ct)) throw new MessageRuleException("Contact required.");

        var row = new DirectMessage
        {
            Sender = message.Sender, Recipient = message.Recipient, Token = message.Token, Body = message.Body
        };
        db.Messages.Add(row);
        await db.SaveChangesAsync(ct);
        if (first == message.Recipient)
            await contact.Where(c => c.HiddenByFirst).ExecuteUpdateAsync(s => s.SetProperty(c => c.HiddenByFirst, false), ct);
        else
            await contact.Where(c => c.HiddenBySecond).ExecuteUpdateAsync(s => s.SetProperty(c => c.HiddenBySecond, false), ct);
        await tx.CommitAsync(ct);
        return row.Id;
    }

    public async Task<List<DirectRow>> Inbox(long owner, long after, CancellationToken ct)
    {
        await using var db = await contexts.CreateDbContextAsync(ct);
        return await db.Messages.Where(m => (m.Sender == owner || m.Recipient == owner) && m.Id > after)
            .OrderBy(m => m.Id).Take(200)
            .Select(m => new DirectRow(m.Id, m.Sender, m.Recipient, m.Body, m.SentAt)).ToListAsync(ct);
    }
}
