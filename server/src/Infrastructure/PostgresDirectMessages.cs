using KitchenTable.Application;
using KitchenTable.Domain;
using Npgsql;

namespace KitchenTable.Infrastructure;

public sealed class PostgresDirectMessages(NpgsqlDataSource db) : IDirectStore
{
    public async Task Initialize(CancellationToken ct)
    {
        await using var cmd = db.CreateCommand("""
            CREATE TABLE IF NOT EXISTS subscribers (
                number bigint GENERATED ALWAYS AS IDENTITY (START WITH 100001) PRIMARY KEY,
                key_hash bytea UNIQUE NOT NULL
            );
            CREATE TABLE IF NOT EXISTS direct_messages (
                id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                sender bigint NOT NULL REFERENCES subscribers(number),
                recipient bigint NOT NULL REFERENCES subscribers(number),
                token uuid NOT NULL, body text NOT NULL, sent_at timestamptz NOT NULL DEFAULT now(),
                CHECK (sender <> recipient), UNIQUE(sender, token)
            );
            CREATE INDEX IF NOT EXISTS direct_sender_cursor ON direct_messages(sender,id);
            CREATE INDEX IF NOT EXISTS direct_recipient_cursor ON direct_messages(recipient,id);
            """);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<long> Identify(byte[] keyHash, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand("SELECT number FROM subscribers WHERE key_hash=$1");
        cmd.Parameters.AddWithValue(keyHash);
        if (await cmd.ExecuteScalarAsync(ct) is long existing) return existing;
        cmd.CommandText = """
            INSERT INTO subscribers(key_hash) VALUES ($1)
            ON CONFLICT(key_hash) DO UPDATE SET key_hash=EXCLUDED.key_hash RETURNING number
            """;
        return (long)(await cmd.ExecuteScalarAsync(ct))!;
    }

    public async Task<long> Append(PersonalMessage message, CancellationToken ct)
    {
        await using var conn = await db.OpenConnectionAsync(ct);
        await using var tx = await conn.BeginTransactionAsync(ct);
        // Allocate history cursors in commit order so a reconnect cannot skip an in-flight insert.
        await using var serial = new NpgsqlCommand("LOCK TABLE direct_messages IN SHARE ROW EXCLUSIVE MODE", conn, tx);
        await serial.ExecuteNonQueryAsync(ct);
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO direct_messages(sender,recipient,token,body)
            SELECT $1,$2,$3,$4 WHERE EXISTS (SELECT 1 FROM contacts WHERE first_number=LEAST($1,$2) AND second_number=GREATEST($1,$2))
            ON CONFLICT(sender,token) DO NOTHING RETURNING id
            """, conn, tx);
        cmd.Parameters.AddWithValue(message.Sender);
        cmd.Parameters.AddWithValue(message.Recipient);
        cmd.Parameters.AddWithValue(message.Token);
        cmd.Parameters.AddWithValue(message.Body);
        var id = (long?)await cmd.ExecuteScalarAsync(ct);
        if (id is null)
        {
            cmd.CommandText = "SELECT id FROM direct_messages WHERE sender=$1 AND recipient=$2 AND token=$3 AND body=$4";
            id = (long?)await cmd.ExecuteScalarAsync(ct)
                ?? throw new MessageRuleException("Contact required or conflicting message token.");
        }
        else
        {
            // Only a newly stored incoming message makes its sender visible again.
            await using var reveal = new NpgsqlCommand("""
                UPDATE contacts SET hidden_by_first = hidden_by_first AND first_number<>$2,
                                    hidden_by_second = hidden_by_second AND second_number<>$2
                WHERE first_number=LEAST($1,$2) AND second_number=GREATEST($1,$2)
                  AND ((first_number=$2 AND hidden_by_first) OR (second_number=$2 AND hidden_by_second))
                """, conn, tx);
            reveal.Parameters.AddWithValue(message.Sender);
            reveal.Parameters.AddWithValue(message.Recipient);
            await reveal.ExecuteNonQueryAsync(ct);
        }
        await tx.CommitAsync(ct);
        return id.Value;
    }

    public async Task<List<DirectRow>> Inbox(long owner, long after, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand("""
            SELECT id,sender,recipient,body,sent_at FROM direct_messages
            WHERE (sender=$1 OR recipient=$1) AND id>$2 ORDER BY id LIMIT 200
            """);
        cmd.Parameters.AddWithValue(owner);
        cmd.Parameters.AddWithValue(after);
        await using var rows = await cmd.ExecuteReaderAsync(ct);
        var messages = new List<DirectRow>();
        while (await rows.ReadAsync(ct))
            messages.Add(new(rows.GetInt64(0), rows.GetInt64(1), rows.GetInt64(2), rows.GetString(3), rows.GetDateTime(4)));
        return messages;
    }
}
