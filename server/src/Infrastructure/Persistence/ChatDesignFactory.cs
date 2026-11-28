using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace KitchenTable.Infrastructure;

public sealed class ChatDesignFactory : IDesignTimeDbContextFactory<ChatDbContext>
{
    public ChatDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<ChatDbContext>()
            .UseNpgsql(Environment.GetEnvironmentVariable("ConnectionStrings__Chat")).Options);
}
