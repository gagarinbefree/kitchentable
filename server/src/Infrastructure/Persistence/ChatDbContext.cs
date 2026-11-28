using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Conventions;

namespace KitchenTable.Infrastructure;

public sealed class ChatDbContext(DbContextOptions<ChatDbContext> options) : DbContext(options)
{
    public DbSet<Subscriber> Subscribers => Set<Subscriber>();
    public DbSet<DirectMessage> Messages => Set<DirectMessage>();
    public DbSet<Contact> Contacts => Set<Contact>();
    public DbSet<ContactInvite> Invitations => Set<ContactInvite>();
    public DbSet<MessageWriteGate> MessageWriteGate => Set<MessageWriteGate>();

    protected override void ConfigureConventions(ModelConfigurationBuilder builder) =>
        builder.Conventions.Remove(typeof(ForeignKeyIndexConvention));

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<Subscriber>(s =>
        {
            s.ToTable("subscribers");
            s.HasKey(x => x.Number).HasName("subscribers_pkey");
            s.Property(x => x.Number).HasColumnName("number").UseIdentityAlwaysColumn().HasIdentityOptions(startValue: 100001);
            s.Property(x => x.KeyHash).HasColumnName("key_hash");
            s.HasAlternateKey(x => x.KeyHash).HasName("subscribers_key_hash_key");
        });

        model.Entity<DirectMessage>(m =>
        {
            m.ToTable("direct_messages", t => t.HasCheckConstraint("direct_messages_check", "sender <> recipient"));
            m.HasKey(x => x.Id).HasName("direct_messages_pkey");
            m.Property(x => x.Id).HasColumnName("id").UseIdentityAlwaysColumn();
            m.Property(x => x.Sender).HasColumnName("sender");
            m.Property(x => x.Recipient).HasColumnName("recipient");
            m.Property(x => x.Token).HasColumnName("token");
            m.Property(x => x.Body).HasColumnName("body");
            m.Property(x => x.SentAt).HasColumnName("sent_at").HasDefaultValueSql("now()");
            m.HasAlternateKey(x => new { x.Sender, x.Token }).HasName("direct_messages_sender_token_key");
            m.HasIndex(x => new { x.Sender, x.Id }).HasDatabaseName("direct_sender_cursor");
            m.HasIndex(x => new { x.Recipient, x.Id }).HasDatabaseName("direct_recipient_cursor");
            m.HasOne<Subscriber>().WithMany().HasForeignKey(x => x.Sender).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("direct_messages_sender_fkey");
            m.HasOne<Subscriber>().WithMany().HasForeignKey(x => x.Recipient).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("direct_messages_recipient_fkey");
        });

        model.Entity<Contact>(c =>
        {
            c.ToTable("contacts", t => t.HasCheckConstraint("contacts_check", "first_number < second_number"));
            c.HasKey(x => new { x.FirstNumber, x.SecondNumber }).HasName("contacts_pkey");
            c.Property(x => x.FirstNumber).HasColumnName("first_number");
            c.Property(x => x.SecondNumber).HasColumnName("second_number");
            c.Property(x => x.HiddenByFirst).HasColumnName("hidden_by_first").HasDefaultValue(false);
            c.Property(x => x.HiddenBySecond).HasColumnName("hidden_by_second").HasDefaultValue(false);
            c.HasIndex(x => x.SecondNumber).HasDatabaseName("contacts_by_second");
            c.HasOne<Subscriber>().WithMany().HasForeignKey(x => x.FirstNumber).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("contacts_first_number_fkey");
            c.HasOne<Subscriber>().WithMany().HasForeignKey(x => x.SecondNumber).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("contacts_second_number_fkey");
        });

        model.Entity<ContactInvite>(i =>
        {
            i.ToTable("contact_invites");
            i.HasKey(x => x.Owner).HasName("contact_invites_pkey");
            i.Property(x => x.Owner).HasColumnName("owner").ValueGeneratedNever();
            i.Property(x => x.Digest).HasColumnName("digest");
            i.Property(x => x.ExpiresAt).HasColumnName("expires_at");
            i.Property(x => x.ClaimedBy).HasColumnName("claimed_by");
            i.HasAlternateKey(x => x.Digest).HasName("contact_invites_digest_key");
            i.HasOne<Subscriber>().WithMany().HasForeignKey(x => x.Owner).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("contact_invites_owner_fkey");
            i.HasOne<Subscriber>().WithMany().HasForeignKey(x => x.ClaimedBy).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("contact_invites_claimed_by_fkey");
        });

        model.Entity<MessageWriteGate>(g =>
        {
            g.ToTable("message_write_gate");
            g.HasKey(x => x.Id);
            g.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
            g.HasData(new MessageWriteGate { Id = 1 });
        });
    }
}
