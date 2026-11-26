using System.Text;

namespace KitchenTable.Domain;

public sealed class MessageRuleException(string message) : Exception(message);

public sealed record DraftMessage
{
    public Guid Sender { get; }
    public Guid Token { get; }
    public string Body { get; }

    private DraftMessage(Guid sender, Guid token, string body) =>
        (Sender, Token, Body) = (sender, token, body);

    public static DraftMessage Create(Guid sender, Guid token, string? text)
    {
        if (sender == Guid.Empty || token == Guid.Empty)
            throw new MessageRuleException("Missing sender or message token.");
        return new DraftMessage(sender, token, NormalizeText(text));
    }

    internal static string NormalizeText(string? text)
    {
        var body = text?.Trim();
        if (string.IsNullOrEmpty(body) || Encoding.UTF8.GetByteCount(body) > 32000)
            throw new MessageRuleException("Message is empty or too long.");
        return body;
    }
}
