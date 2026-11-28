using KitchenTable.Application;
using KitchenTable.Domain;
using Npgsql;

namespace KitchenTable.Infrastructure;

public sealed class PostgresContacts(NpgsqlDataSource db) : IContactStore
{
    public async Task Initialize(CancellationToken ct)
    {
        await using var cmd = db.CreateCommand("""
            CREATE TABLE IF NOT EXISTS contacts (
                first_number bigint NOT NULL REFERENCES subscribers(number),
                second_number bigint NOT NULL REFERENCES subscribers(number),
                CHECK (first_number < second_number), PRIMARY KEY(first_number,second_number)
            );
            ALTER TABLE contacts ADD COLUMN IF NOT EXISTS hidden_by_first boolean NOT NULL DEFAULT false,
                                 ADD COLUMN IF NOT EXISTS hidden_by_second boolean NOT NULL DEFAULT false;
            CREATE INDEX IF NOT EXISTS contacts_by_second ON contacts(second_number);
            CREATE TABLE IF NOT EXISTS contact_invites (
                owner bigint PRIMARY KEY REFERENCES subscribers(number),
                digest bytea UNIQUE NOT NULL, expires_at timestamptz NOT NULL,
                claimed_by bigint REFERENCES subscribers(number)
            );
            """);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<List<long>> List(long owner, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand("""
            SELECT second_number FROM contacts WHERE first_number=$1 AND NOT hidden_by_first
            UNION ALL
            SELECT first_number FROM contacts WHERE second_number=$1 AND NOT hidden_by_second ORDER BY 1
            """);
        cmd.Parameters.AddWithValue(owner);
        await using var rows = await cmd.ExecuteReaderAsync(ct);
        var peers = new List<long>();
        while (await rows.ReadAsync(ct)) peers.Add(rows.GetInt64(0));
        return peers;
    }

    public async Task<bool> Hide(long owner, long peer, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand("""
            UPDATE contacts SET hidden_by_first = hidden_by_first OR first_number=$1,
                                hidden_by_second = hidden_by_second OR second_number=$1
            WHERE first_number=LEAST($1,$2) AND second_number=GREATEST($1,$2)
              AND ((first_number=$1 AND NOT hidden_by_first) OR (second_number=$1 AND NOT hidden_by_second))
            """);
        cmd.Parameters.AddWithValue(owner);
        cmd.Parameters.AddWithValue(peer);
        return await cmd.ExecuteNonQueryAsync(ct) > 0;
    }

    public async Task SaveInvite(long owner, byte[] digest, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand("""
            INSERT INTO contact_invites(owner,digest,expires_at) VALUES($1,$2,now()+interval '5 minutes')
            ON CONFLICT(owner) DO UPDATE SET digest=excluded.digest, expires_at=excluded.expires_at, claimed_by=NULL
            """);
        cmd.Parameters.AddWithValue(owner);
        cmd.Parameters.AddWithValue(digest);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<long> Preview(long scanner, byte[] digest, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand("""
            SELECT owner FROM contact_invites WHERE digest=$1 AND owner<>$2 AND expires_at>now()
                AND (claimed_by IS NULL OR claimed_by=$2)
            """);
        cmd.Parameters.AddWithValue(digest);
        cmd.Parameters.AddWithValue(scanner);
        return await cmd.ExecuteScalarAsync(ct) as long? ?? throw new MessageRuleException("QR invitation unavailable.");
    }

    public async Task<long> Accept(long scanner, byte[] digest, CancellationToken ct)
    {
        await using var conn = await db.OpenConnectionAsync(ct);
        await using var tx = await conn.BeginTransactionAsync(ct);
        await using var claim = new NpgsqlCommand("""
            UPDATE contact_invites SET claimed_by=$2 WHERE digest=$1 AND owner<>$2 AND expires_at>now()
                AND claimed_by IS NULL RETURNING owner
            """, conn, tx);
        claim.Parameters.AddWithValue(digest);
        claim.Parameters.AddWithValue(scanner);
        if (await claim.ExecuteScalarAsync(ct) is not long owner)
        {
            // A retry acknowledges the original acceptance without undoing a later hide.
            claim.CommandText = """
                SELECT owner FROM contact_invites WHERE digest=$1 AND claimed_by=$2 AND expires_at>now()
                """;
            return await claim.ExecuteScalarAsync(ct) as long? ?? throw new MessageRuleException("QR invitation unavailable.");
        }
        await using var link = new NpgsqlCommand("""
            INSERT INTO contacts(first_number,second_number) VALUES($1,$2)
            ON CONFLICT(first_number,second_number) DO UPDATE SET hidden_by_first=false, hidden_by_second=false
            """, conn, tx);
        link.Parameters.AddWithValue(Math.Min(owner, scanner));
        link.Parameters.AddWithValue(Math.Max(owner, scanner));
        await link.ExecuteNonQueryAsync(ct);
        await tx.CommitAsync(ct);
        return owner;
    }
}
