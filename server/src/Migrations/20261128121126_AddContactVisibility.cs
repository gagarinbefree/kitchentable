using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace KitchenTable.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddContactVisibility : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "hidden_by_first",
                table: "contacts",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "hidden_by_second",
                table: "contacts",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "hidden_by_first",
                table: "contacts");

            migrationBuilder.DropColumn(
                name: "hidden_by_second",
                table: "contacts");
        }
    }
}
