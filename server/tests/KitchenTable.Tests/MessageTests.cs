using KitchenTable.Domain;
using Xunit;

namespace KitchenTable.Tests;

[Trait("Category", "Unit")]
public class MessageTests
{
    [Theory]
    [InlineData("")]
    [InlineData("  \n ")]
    public void Empty_text_cannot_be_sent(string text) =>
        Assert.Throws<MessageRuleException>(() => DraftMessage.Create(Guid.NewGuid(), Guid.NewGuid(), text));

    [Fact]
    public void Trims_outer_spaces_and_preserves_multiline_text()
    {
        var message = DraftMessage.Create(Guid.NewGuid(), Guid.NewGuid(), "  Привет!\n👋  ");
        Assert.Equal("Привет!\n👋", message.Body);
    }

    [Fact]
    public void Requires_an_identity_and_a_retry_token()
    {
        Assert.Throws<MessageRuleException>(() => DraftMessage.Create(Guid.Empty, Guid.NewGuid(), "А"));
        Assert.Throws<MessageRuleException>(() => DraftMessage.Create(Guid.NewGuid(), Guid.Empty, "Б"));
    }
}
