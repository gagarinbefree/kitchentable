namespace KitchenTable.Domain;

public sealed record PersonalMessage
{
    public long Sender { get; }
    public long Recipient { get; }
    public Guid Token { get; }
    public string Body { get; }

    private PersonalMessage(long sender, long recipient, Guid token, string body) =>
        (Sender, Recipient, Token, Body) = (sender, recipient, token, body);

    public static PersonalMessage Create(long sender, long recipient, Guid token, string? text)
    {
        if (sender <= 0 || recipient <= 0 || sender == recipient)
            throw new MessageRuleException("Choose another subscriber.");
        if (token == Guid.Empty) throw new MessageRuleException("Missing message token.");
        return new(sender, recipient, token, DraftMessage.NormalizeText(text));
    }
}
