using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AgroSolutions.Identity.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialOutbox : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "OutboxMessages",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    EventType = table.Column<string>(
                        type: "character varying(500)",
                        maxLength: 500,
                        nullable: false
                    ),
                    Payload = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTime>(
                        type: "timestamp with time zone",
                        nullable: false
                    ),
                    ProcessedAt = table.Column<DateTime>(
                        type: "timestamp with time zone",
                        nullable: true
                    ),
                    RetryCount = table.Column<int>(type: "integer", nullable: false),
                    ErrorMessage = table.Column<string>(
                        type: "character varying(2000)",
                        maxLength: 2000,
                        nullable: true
                    ),
                    Status = table.Column<int>(type: "integer", nullable: false),
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OutboxMessages", x => x.Id);
                }
            );

            migrationBuilder.CreateIndex(
                name: "IX_OutboxMessages_ProcessedAt",
                table: "OutboxMessages",
                column: "ProcessedAt"
            );

            migrationBuilder.CreateIndex(
                name: "IX_OutboxMessages_Status_CreatedAt",
                table: "OutboxMessages",
                columns: new[] { "Status", "CreatedAt" }
            );
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(name: "OutboxMessages");
        }
    }
}
