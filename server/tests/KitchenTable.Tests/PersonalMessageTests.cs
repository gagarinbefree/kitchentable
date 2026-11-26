using KitchenTable.Domain;
using Xunit;

namespace KitchenTable.Tests;

[Trait("Category", "Unit")]
public class PersonalMessageTests
{
    [Theory]
    [InlineData(0, 100002)]
    [InlineData(100001, 0)]
    [InlineData(100001, 100001)]
    public void Requires_two_distinct_subscribers(long sender, long recipient) =>
        Assert.Throws<MessageRuleException>(() => PersonalMessage.Create(sender, recipient, Guid.NewGuid(), "Hello"));

    [Fact]
    public void Preserves_participants_and_retry_token()
    {
        var token = Guid.NewGuid();
        var message = PersonalMessage.Create(100001, 100002, token, "  Hello  ");
        Assert.Equal((100001L, 100002L, token, "Hello"), (message.Sender, message.Recipient, message.Token, message.Body));
    }
}
