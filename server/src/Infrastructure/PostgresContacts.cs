using KitchenTable.Application;
using KitchenTable.Domain;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace KitchenTable.Infrastructure;

public sealed class PostgresContacts(IDbContextFactory<ChatDbContext> contexts) : IContactStore
{
    public async Task<List<long>> List(long owner, CancellationToken ct)
    {
        await using var db = await contexts.CreateDbContextAsync(ct);
        return await db.Contacts.Where(c => c.FirstNumber == owner && !c.HiddenByFirst).Select(c => c.SecondNumber)
            .Concat(db.Contacts.Where(c => c.SecondNumber == owner && !c.HiddenBySecond).Select(c => c.FirstNumber))
            .Order().ToListAsync(ct);
    }

    public async Task<bool> Hide(long owner, long peer, CancellationToken ct)
    {
        await using var db = await contexts.CreateDbContextAsync(ct);
        var pair = db.Contacts.Where(c => c.FirstNumber == Math.Min(owner, peer) && c.SecondNumber == Math.Max(owner, peer));
        var affected = owner < peer
            ? await pair.Where(c => !c.HiddenByFirst).ExecuteUpdateAsync(s => s.SetProperty(c => c.HiddenByFirst, true), ct)
            : await pair.Where(c => !c.HiddenBySecond).ExecuteUpdateAsync(s => s.SetProperty(c => c.HiddenBySecond, true), ct);
        return affected > 0;
    }

    public async Task SaveInvite(long owner, byte[] digest, CancellationToken ct)
    {
        await using var db = await contexts.CreateDbContextAsync(ct);
        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(5);
        var invite = new ContactInvite { Owner = owner, Digest = digest, ExpiresAt = expiresAt };
        await InsertOrUpdate(db, invite, "contact_invites_pkey", () =>
            db.Invitations.Where(i => i.Owner == owner).ExecuteUpdateAsync(s => s
                .SetProperty(i => i.Digest, digest).SetProperty(i => i.ExpiresAt, expiresAt)
                .SetProperty(i => i.ClaimedBy, (long?)null), ct), ct);
    }

    private static IQueryable<ContactInvite> Available(ChatDbContext db, long scanner, byte[] digest) =>
        db.Invitations.Where(i => i.Digest == digest && i.Owner != scanner && i.ExpiresAt > DateTimeOffset.UtcNow &&
                                  (i.ClaimedBy == null || i.ClaimedBy == scanner));

    public async Task<long> Preview(long scanner, byte[] digest, CancellationToken ct)
    {
        await using var db = await contexts.CreateDbContextAsync(ct);
        return await Available(db, scanner, digest).Select(i => (long?)i.Owner).SingleOrDefaultAsync(ct)
            ?? throw new MessageRuleException("QR invitation unavailable.");
    }

    public async Task<long> Accept(long scanner, byte[] digest, CancellationToken ct)
    {
        await using var db = await contexts.CreateDbContextAsync(ct);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var invite = Available(db, scanner, digest);
        var claimed = await invite.Where(i => i.ClaimedBy == null)
            .ExecuteUpdateAsync(s => s.SetProperty(i => i.ClaimedBy, scanner), ct);
        var owner = await invite.Where(i => i.ClaimedBy == scanner).Select(i => (long?)i.Owner).SingleOrDefaultAsync(ct)
            ?? throw new MessageRuleException("QR invitation unavailable.");
        if (claimed == 0) return owner;

        var first = Math.Min(scanner, owner);
        var second = Math.Max(scanner, owner);
        await InsertOrUpdate(db, new Contact { FirstNumber = first, SecondNumber = second }, "contacts_pkey", () =>
            db.Contacts.Where(c => c.FirstNumber == first && c.SecondNumber == second)
                .ExecuteUpdateAsync(s => s.SetProperty(c => c.HiddenByFirst, false).SetProperty(c => c.HiddenBySecond, false), ct), ct);
        await tx.CommitAsync(ct);
        return owner;
    }

    private static async Task InsertOrUpdate<TEntity>(ChatDbContext db, TEntity row, string primaryKey,
        Func<Task<int>> update, CancellationToken ct) where TEntity : class
    {
        if (await update() != 0) return;
        db.Add(row);
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException e) when (e.InnerException is PostgresException
            { SqlState: PostgresErrorCodes.UniqueViolation } pg && pg.ConstraintName == primaryKey)
        {
            // SaveChanges rolls back its savepoint if another writer inserted the same row.
            db.Entry(row).State = EntityState.Detached;
            await update();
        }
    }
}
