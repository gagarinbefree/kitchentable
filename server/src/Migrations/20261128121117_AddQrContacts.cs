using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace KitchenTable.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddQrContacts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "contact_invites",
                columns: table => new
                {
                    owner = table.Column<long>(type: "bigint", nullable: false),
                    digest = table.Column<byte[]>(type: "bytea", nullable: false),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    claimed_by = table.Column<long>(type: "bigint", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("contact_invites_pkey", x => x.owner);
                    table.UniqueConstraint("contact_invites_digest_key", x => x.digest);
                    table.ForeignKey(
                        name: "contact_invites_claimed_by_fkey",
                        column: x => x.claimed_by,
                        principalTable: "subscribers",
                        principalColumn: "number");
                    table.ForeignKey(
                        name: "contact_invites_owner_fkey",
                        column: x => x.owner,
                        principalTable: "subscribers",
                        principalColumn: "number");
                });

            migrationBuilder.CreateTable(
                name: "contacts",
                columns: table => new
                {
                    first_number = table.Column<long>(type: "bigint", nullable: false),
                    second_number = table.Column<long>(type: "bigint", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("contacts_pkey", x => new { x.first_number, x.second_number });
                    table.CheckConstraint("contacts_check", "first_number < second_number");
                    table.ForeignKey(
                        name: "contacts_first_number_fkey",
                        column: x => x.first_number,
                        principalTable: "subscribers",
                        principalColumn: "number");
                    table.ForeignKey(
                        name: "contacts_second_number_fkey",
                        column: x => x.second_number,
                        principalTable: "subscribers",
                        principalColumn: "number");
                });

            migrationBuilder.CreateIndex(
                name: "contacts_by_second",
                table: "contacts",
                column: "second_number");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "contact_invites");

            migrationBuilder.DropTable(
                name: "contacts");
        }
    }
}
