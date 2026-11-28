using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace KitchenTable.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class CreateMessaging : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "subscribers",
                columns: table => new
                {
                    number = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:IdentitySequenceOptions", "'100001', '1', '', '', 'False', '1'")
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    key_hash = table.Column<byte[]>(type: "bytea", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("subscribers_pkey", x => x.number);
                    table.UniqueConstraint("subscribers_key_hash_key", x => x.key_hash);
                });

            migrationBuilder.CreateTable(
                name: "direct_messages",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    sender = table.Column<long>(type: "bigint", nullable: false),
                    recipient = table.Column<long>(type: "bigint", nullable: false),
                    token = table.Column<Guid>(type: "uuid", nullable: false),
                    body = table.Column<string>(type: "text", nullable: false),
                    sent_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("direct_messages_pkey", x => x.id);
                    table.UniqueConstraint("direct_messages_sender_token_key", x => new { x.sender, x.token });
                    table.CheckConstraint("direct_messages_check", "sender <> recipient");
                    table.ForeignKey(
                        name: "direct_messages_recipient_fkey",
                        column: x => x.recipient,
                        principalTable: "subscribers",
                        principalColumn: "number");
                    table.ForeignKey(
                        name: "direct_messages_sender_fkey",
                        column: x => x.sender,
                        principalTable: "subscribers",
                        principalColumn: "number");
                });

            migrationBuilder.CreateIndex(
                name: "direct_recipient_cursor",
                table: "direct_messages",
                columns: new[] { "recipient", "id" });

            migrationBuilder.CreateIndex(
                name: "direct_sender_cursor",
                table: "direct_messages",
                columns: new[] { "sender", "id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "direct_messages");

            migrationBuilder.DropTable(
                name: "subscribers");
        }
    }
}
