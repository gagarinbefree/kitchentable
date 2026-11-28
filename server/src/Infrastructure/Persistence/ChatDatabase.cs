using KitchenTable.Infrastructure.Migrations;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using Microsoft.EntityFrameworkCore.Storage;
using System.Reflection;

namespace KitchenTable.Infrastructure;

internal static class ChatDatabase
{
    public static async Task Migrate(ChatDbContext db, CancellationToken ct)
    {
        if (await db.Database.CanConnectAsync(ct) &&
            !(await db.Database.GetAppliedMigrationsAsync(ct)).Any())
            await AdoptLegacySchema(db, ct);

        await db.Database.MigrateAsync(ct);
    }

    // Releases before EF created these tables in place. Record only complete historical
    // migration steps that already exist; EF applies the rest normally.
    private static async Task AdoptLegacySchema(ChatDbContext db, CancellationToken ct)
    {
        var history = db.GetService<IHistoryRepository>();
        await history.CreateIfNotExistsAsync(ct);
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        await using var migrationLock = await history.AcquireDatabaseLockAsync(ct);
        if ((await history.GetAppliedMigrationsAsync(ct)).Count != 0) return;

        var options = new DbContextOptionsBuilder<LegacyCatalog>()
            .UseNpgsql(db.Database.GetDbConnection()).Options;
        await using var catalog = new LegacyCatalog(options);
        await catalog.Database.UseTransactionAsync(tx.GetDbTransaction(), ct);
        string[] tables = ["subscribers", "direct_messages", "contacts", "contact_invites"];
        var existing = await catalog.Columns.Where(c => c.Schema == "public" && tables.Contains(c.Table))
            .ToDictionaryAsync(c => (c.Table, c.Name), ct);

        Migration[] legacy = [new CreateMessaging(), new AddQrContacts(), new AddContactVisibility()];
        var gap = false;
        foreach (var migration in legacy)
        {
            var columns = migration.UpOperations.OfType<CreateTableOperation>().SelectMany(t => t.Columns)
                .Concat(migration.UpOperations.OfType<AddColumnOperation>()).ToList();
            if (!columns.Any(c => existing.ContainsKey((c.Table, c.Name))))
            {
                gap = true;
                continue;
            }
            if (gap || columns.Any(c => !existing.TryGetValue((c.Table, c.Name), out var actual) ||
                    actual.Type != c.ColumnType || (actual.Nullable == "YES") != c.IsNullable))
                throw new InvalidOperationException($"Incomplete legacy schema for {migration.GetType().Name}.");

            var id = migration.GetType().GetCustomAttribute<MigrationAttribute>()!.Id;
            catalog.Applied.Add(new HistoryRow(id, ProductInfo.GetVersion()));
        }
        await catalog.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
    }

    private sealed class LegacyColumn
    {
        public required string Schema { get; init; }
        public required string Table { get; init; }
        public required string Name { get; init; }
        public required string Type { get; init; }
        public required string Nullable { get; init; }
    }

    private sealed class LegacyCatalog(DbContextOptions<LegacyCatalog> options) : DbContext(options)
    {
        public DbSet<LegacyColumn> Columns => Set<LegacyColumn>();
        public DbSet<HistoryRow> Applied => Set<HistoryRow>();

        protected override void OnModelCreating(ModelBuilder model)
        {
            model.Entity<LegacyColumn>(c =>
            {
                c.HasNoKey().ToView("columns", "information_schema");
                c.Property(x => x.Schema).HasColumnName("table_schema");
                c.Property(x => x.Table).HasColumnName("table_name");
                c.Property(x => x.Name).HasColumnName("column_name");
                c.Property(x => x.Type).HasColumnName("data_type");
                c.Property(x => x.Nullable).HasColumnName("is_nullable");
            });
            model.Entity<HistoryRow>(h =>
            {
                h.ToTable(HistoryRepository.DefaultTableName);
                h.HasKey(x => x.MigrationId);
                h.Property(x => x.ProductVersion);
            });
        }
    }
}
