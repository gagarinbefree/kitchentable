namespace KitchenTable.Infrastructure;

public sealed class Subscriber
{
    public long Number { get; set; }
    public required byte[] KeyHash { get; set; }
}

public sealed class DirectMessage
{
    public long Id { get; set; }
    public long Sender { get; set; }
    public long Recipient { get; set; }
    public Guid Token { get; set; }
    public required string Body { get; set; }
    public DateTimeOffset SentAt { get; set; }
}

public sealed class Contact
{
    public long FirstNumber { get; set; }
    public long SecondNumber { get; set; }
    public bool HiddenByFirst { get; set; }
    public bool HiddenBySecond { get; set; }
}

public sealed class ContactInvite
{
    public long Owner { get; set; }
    public required byte[] Digest { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public long? ClaimedBy { get; set; }
}

// The single row orders message inserts across server instances.
public sealed class MessageWriteGate
{
    public int Id { get; set; }
}
