using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace KitchenTable.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class OrderMessageWrites : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "message_write_gate",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_message_write_gate", x => x.id);
                });

            migrationBuilder.InsertData(
                table: "message_write_gate",
                column: "id",
                value: 1);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "message_write_gate");
        }
    }
}
