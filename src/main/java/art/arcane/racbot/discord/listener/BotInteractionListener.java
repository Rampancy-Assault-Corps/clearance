package art.arcane.racbot.discord.listener;

import art.arcane.racbot.app.BotRuntimeComponents;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Set;
import java.util.function.Supplier;
import net.dv8tion.jda.api.audit.ActionType;
import net.dv8tion.jda.api.audit.AuditLogChange;
import net.dv8tion.jda.api.audit.AuditLogEntry;
import net.dv8tion.jda.api.audit.AuditLogKey;
import net.dv8tion.jda.api.entities.Guild;
import net.dv8tion.jda.api.entities.Message;
import net.dv8tion.jda.api.entities.User;
import net.dv8tion.jda.api.entities.channel.concrete.TextChannel;
import net.dv8tion.jda.api.entities.emoji.Emoji;
import net.dv8tion.jda.api.events.guild.GuildAuditLogEntryCreateEvent;
import net.dv8tion.jda.api.events.guild.member.GuildMemberJoinEvent;
import net.dv8tion.jda.api.events.guild.member.GuildMemberRemoveEvent;
import net.dv8tion.jda.api.events.interaction.command.SlashCommandInteractionEvent;
import net.dv8tion.jda.api.events.message.MessageDeleteEvent;
import net.dv8tion.jda.api.events.message.MessageUpdateEvent;
import net.dv8tion.jda.api.events.message.react.MessageReactionAddEvent;
import net.dv8tion.jda.api.hooks.ListenerAdapter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class BotInteractionListener extends ListenerAdapter {
  private static final Logger LOGGER = LoggerFactory.getLogger(BotInteractionListener.class);
  private static final String HEART_EMOJI = "\u2764\uFE0F";
  private static final Set<String> HEART_REACTION_NAMES =
      Set.of("\u2764", "\u2764\uFE0F", "\u2665");
  private static final int MAX_CONTENT_PREVIEW = 900;

  private final Supplier<BotRuntimeComponents> runtime;

  public BotInteractionListener(Supplier<BotRuntimeComponents> runtime) {
    this.runtime = runtime;
  }

  @Override
  public void onSlashCommandInteraction(SlashCommandInteractionEvent event) {
    if (!"ping".equals(event.getName())) {
      event.reply("Unknown command.").setEphemeral(true).queue();
      return;
    }

    BotRuntimeComponents components = runtime.get();
    if (!components.config().features().pingEnabled()) {
      event.reply("`/ping` is disabled.").setEphemeral(true).queue();
      return;
    }

    event
        .reply("Pong! Gateway ping: `" + event.getJDA().getGatewayPing() + "ms`")
        .setEphemeral(true)
        .queue();
  }

  @Override
  public void onMessageReactionAdd(MessageReactionAddEvent event) {
    if (!event.isFromGuild()) {
      return;
    }

    User reactor = event.getUser();
    if (reactor == null || reactor.isBot()) {
      return;
    }

    if (event.getReaction().getEmoji().getType() != Emoji.Type.UNICODE) {
      return;
    }

    String reactionName = event.getReaction().getEmoji().getName();
    if (!isSupportedHeartEmoji(reactionName)) {
      return;
    }

    BotRuntimeComponents components = runtime.get();
    Long targetUserId = components.config().logs().heartTargetUserId();
    if (targetUserId == null || targetUserId <= 0) {
      return;
    }

    event
        .retrieveMessage()
        .queue(
            message -> {
              if (message.getAuthor().getIdLong() != targetUserId) {
                return;
              }

              message
                  .addReaction(Emoji.fromUnicode(HEART_EMOJI))
                  .queue(
                      success -> {},
                      error ->
                          LOGGER.debug(
                              "Failed to add mirrored heart reaction in channel {} for message {}",
                              event.getChannel().getId(),
                              event.getMessageId(),
                              error));
            },
            error ->
                LOGGER.debug(
                    "Failed to fetch message {} in channel {} for heart mirror",
                    event.getMessageId(),
                    event.getChannel().getId(),
                    error));
  }

  @Override
  public void onGuildMemberJoin(GuildMemberJoinEvent event) {
    BotRuntimeComponents components = runtime.get();
    TextChannel channel =
        resolveLogChannel(event.getGuild(), components.config().logs().userLogChannelId());
    if (channel == null) {
      return;
    }

    channel
        .sendMessageEmbeds(
            components
                .embedFactory()
                .base("User Joined")
                .setDescription(
                    event.getUser().getAsMention()
                        + " joined the server.\nUser ID: `"
                        + event.getUser().getId()
                        + "`")
                .build())
        .queue();
  }

  @Override
  public void onGuildMemberRemove(GuildMemberRemoveEvent event) {
    BotRuntimeComponents components = runtime.get();
    TextChannel channel =
        resolveLogChannel(event.getGuild(), components.config().logs().userLogChannelId());
    if (channel == null || event.getUser() == null) {
      return;
    }

    channel
        .sendMessageEmbeds(
            components
                .embedFactory()
                .base("User Left")
                .setDescription(
                    event.getUser().getAsMention()
                        + " left or was removed.\nUser ID: `"
                        + event.getUser().getId()
                        + "`")
                .build())
        .queue();
  }

  @Override
  public void onMessageUpdate(MessageUpdateEvent event) {
    if (!event.isFromGuild()) {
      return;
    }

    BotRuntimeComponents components = runtime.get();
    TextChannel channel =
        resolveLogChannel(event.getGuild(), components.config().logs().commLogChannelId());
    if (channel == null || event.getAuthor().isBot()) {
      return;
    }

    Message message = event.getMessage();
    String contentPreview = truncate(message.getContentDisplay(), MAX_CONTENT_PREVIEW);
    if (contentPreview.isBlank()) {
      contentPreview = "[No text content]";
    }

    channel
        .sendMessageEmbeds(
            components
                .embedFactory()
                .base("Message Edited")
                .setDescription(
                    "Author: "
                        + event.getAuthor().getAsMention()
                        + "\nChannel: "
                        + event.getChannel().getAsMention())
                .addField("Updated Content", contentPreview, false)
                .addField("Jump", "[Open Message](" + message.getJumpUrl() + ")", false)
                .build())
        .queue();
  }

  @Override
  public void onMessageDelete(MessageDeleteEvent event) {
    if (!event.isFromGuild()) {
      return;
    }

    BotRuntimeComponents components = runtime.get();
    TextChannel channel =
        resolveLogChannel(event.getGuild(), components.config().logs().commLogChannelId());
    if (channel == null) {
      return;
    }

    String channelMention = "<#" + event.getChannel().getId() + ">";
    channel
        .sendMessageEmbeds(
            components
                .embedFactory()
                .base("Message Deleted")
                .setDescription(
                    "Message ID: `"
                        + event.getMessageId()
                        + "`\nChannel: "
                        + channelMention
                        + "\nAuthor: unknown (Discord delete events do not include author data)")
                .build())
        .queue();
  }

  @Override
  public void onGuildAuditLogEntryCreate(GuildAuditLogEntryCreateEvent event) {
    BotRuntimeComponents components = runtime.get();
    TextChannel channel =
        resolveLogChannel(event.getGuild(), components.config().logs().auditLogChannelId());
    if (channel == null) {
      return;
    }

    AuditLogEntry entry = event.getEntry();
    ActionType actionType = entry.getType();
    if (actionType == ActionType.KICK) {
      channel
          .sendMessageEmbeds(
              components
                  .embedFactory()
                  .base("Member Kicked")
                  .setDescription(
                      "Moderator: "
                          + mention(entry.getUserIdLong())
                          + "\nTarget: "
                          + mention(entry.getTargetIdLong())
                          + "\nReason: "
                          + defaultReason(entry.getReason()))
                  .build())
          .queue();
      return;
    }

    if (actionType == ActionType.BAN) {
      channel
          .sendMessageEmbeds(
              components
                  .embedFactory()
                  .base("Member Banned")
                  .setDescription(
                      "Moderator: "
                          + mention(entry.getUserIdLong())
                          + "\nTarget: "
                          + mention(entry.getTargetIdLong())
                          + "\nReason: "
                          + defaultReason(entry.getReason()))
                  .build())
          .queue();
      return;
    }

    if (actionType == ActionType.MEMBER_UPDATE) {
      AuditLogChange timeoutChange = entry.getChangeByKey(AuditLogKey.MEMBER_TIME_OUT);
      if (timeoutChange == null) {
        return;
      }

      Object timeoutEnd = timeoutChange.getNewValue();
      String timeoutText;
      if (timeoutEnd instanceof OffsetDateTime time) {
        timeoutText = DateTimeFormatter.ISO_OFFSET_DATE_TIME.format(time);
      } else if (timeoutEnd == null) {
        timeoutText = "timeout removed";
      } else {
        timeoutText = String.valueOf(timeoutEnd);
      }

      channel
          .sendMessageEmbeds(
              components
                  .embedFactory()
                  .base("Member Timed Out")
                  .setDescription(
                      "Moderator: "
                          + mention(entry.getUserIdLong())
                          + "\nTarget: "
                          + mention(entry.getTargetIdLong())
                          + "\nTimeout Until: "
                          + timeoutText
                          + "\nReason: "
                          + defaultReason(entry.getReason()))
                  .build())
          .queue();
    }
  }

  private static TextChannel resolveLogChannel(Guild guild, Long channelId) {
    if (channelId == null || channelId <= 0) {
      return null;
    }
    return guild.getTextChannelById(channelId);
  }

  private static String defaultReason(String reason) {
    return reason == null || reason.isBlank() ? "No reason provided" : reason;
  }

  private static String mention(long userId) {
    return userId <= 0 ? "`unknown`" : "<@" + userId + ">";
  }

  private static String truncate(String value, int maxLength) {
    if (value == null || value.isBlank()) {
      return "";
    }
    if (value.length() <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength - 3) + "...";
  }

  static boolean isSupportedHeartEmoji(String reactionName) {
    return HEART_REACTION_NAMES.contains(reactionName);
  }
}
