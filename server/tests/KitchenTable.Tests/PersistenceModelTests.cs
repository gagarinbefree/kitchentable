using KitchenTable.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace KitchenTable.Tests;

[Trait("Category", "Unit")]
public sealed class PersistenceModelTests
{
    [Fact]
    public void Schema_changes_are_tracked_by_migrations()
    {
        using var db = new ChatDbContext(new DbContextOptionsBuilder<ChatDbContext>()
            .UseNpgsql("Host=localhost;Database=model_only").Options);
        Assert.NotEmpty(db.Database.GetMigrations());
        Assert.False(db.Database.HasPendingModelChanges());
    }
}
