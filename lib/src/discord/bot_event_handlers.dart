import 'dart:async';

import 'package:nyxx/nyxx.dart';
import 'package:racbot_nyxx/src/model/bot_runtime_components.dart';
import 'package:racbot_nyxx/src/util/app_logger.dart';
import 'package:racbot_nyxx/src/util/discord_formatters.dart';
import 'package:racbot_nyxx/src/util/reaction_utils.dart';
import 'package:racbot_nyxx/src/util/text_utils.dart';

typedef RuntimeProvider = BotRuntimeComponents? Function();

class BotEventHandlers {
  static const int maxContentPreview = 900;

  final RuntimeProvider runtimeProvider;
  final AppLogger logger;

  const BotEventHandlers({required this.runtimeProvider, required this.logger});

  List<StreamSubscription<dynamic>> register({required NyxxGateway client}) {
    StreamSubscription<GuildMemberAddEvent> memberAddSubscription = client
        .onGuildMemberAdd
        .listen((GuildMemberAddEvent event) {
          _onGuildMemberAdd(client: client, event: event);
        });

    StreamSubscription<GuildMemberRemoveEvent> memberRemoveSubscription = client
        .onGuildMemberRemove
        .listen((GuildMemberRemoveEvent event) {
          _onGuildMemberRemove(client: client, event: event);
        });

    StreamSubscription<MessageUpdateEvent> messageUpdateSubscription = client
        .onMessageUpdate
        .listen((MessageUpdateEvent event) {
          _onMessageUpdate(client: client, event: event);
        });

    StreamSubscription<MessageDeleteEvent> messageDeleteSubscription = client
        .onMessageDelete
        .listen((MessageDeleteEvent event) {
          _onMessageDelete(client: client, event: event);
        });

    StreamSubscription<MessageReactionAddEvent> reactionAddSubscription = client
        .onMessageReactionAdd
        .listen((MessageReactionAddEvent event) {
          _onMessageReactionAdd(client: client, event: event);
        });

    StreamSubscription<GuildAuditLogCreateEvent> auditLogSubscription = client
        .onGuildAuditLogCreate
        .listen((GuildAuditLogCreateEvent event) {
          _onGuildAuditLogCreate(client: client, event: event);
        });

    return <StreamSubscription<dynamic>>[
      memberAddSubscription,
      memberRemoveSubscription,
      messageUpdateSubscription,
      messageDeleteSubscription,
      reactionAddSubscription,
      auditLogSubscription,
    ];
  }

  Future<void> _onGuildMemberAdd({
    required NyxxGateway client,
    required GuildMemberAddEvent event,
  }) async {
    BotRuntimeComponents? components = runtimeProvider();
    if (components == null) {
      return;
    }

    PartialTextChannel? channel = _resolveLogChannel(
      client: client,
      channelId: components.config.logs.userLogChannelId,
    );
    if (channel == null) {
      return;
    }

    User? user = event.member.user;
    if (user == null) {
      return;
    }

    String description =
        '${DiscordFormatters.userMention(userId: user.id.value)} joined the server.\nUser ID: `${user.id.value}`';

    EmbedBuilder embed = components.embedFactory.base(title: 'User Joined')
      ..description = description;

    await channel.sendMessage(MessageBuilder(embeds: <EmbedBuilder>[embed]));
  }

  Future<void> _onGuildMemberRemove({
    required NyxxGateway client,
    required GuildMemberRemoveEvent event,
  }) async {
    BotRuntimeComponents? components = runtimeProvider();
    if (components == null) {
      return;
    }

    PartialTextChannel? channel = _resolveLogChannel(
      client: client,
      channelId: components.config.logs.userLogChannelId,
    );
    if (channel == null) {
      return;
    }

    User user = event.user;
    String description =
        '${DiscordFormatters.userMention(userId: user.id.value)} left or was removed.\nUser ID: `${user.id.value}`';

    EmbedBuilder embed = components.embedFactory.base(title: 'User Left')
      ..description = description;

    await channel.sendMessage(MessageBuilder(embeds: <EmbedBuilder>[embed]));
  }

  Future<void> _onMessageUpdate({
    required NyxxGateway client,
    required MessageUpdateEvent event,
  }) async {
    if (event.guildId == null) {
      return;
    }

    BotRuntimeComponents? components = runtimeProvider();
    if (components == null) {
      return;
    }

    PartialTextChannel? channel = _resolveLogChannel(
      client: client,
      channelId: components.config.logs.commLogChannelId,
    );
    if (channel == null) {
      return;
    }

    MessageAuthor author = event.message.author;
    if (author is User && author.isBot) {
      return;
    }

    String contentPreview = TextUtils.truncate(
      value: event.message.content,
      maxLength: maxContentPreview,
    );
    if (contentPreview.trim().isEmpty) {
      contentPreview = '[No text content]';
    }

    String jumpUrl = DiscordFormatters.messageJumpUrl(
      guildId: event.guildId!.value,
      channelId: event.message.channelId.value,
      messageId: event.message.id.value,
    );

    String authorMention = DiscordFormatters.userMention(
      userId: author.id.value,
    );
    String channelMention = DiscordFormatters.channelMention(
      channelId: event.message.channelId.value,
    );

    EmbedBuilder embed = components.embedFactory.base(title: 'Message Edited')
      ..description = 'Author: $authorMention\nChannel: $channelMention'
      ..fields = <EmbedFieldBuilder>[
        EmbedFieldBuilder(
          name: 'Updated Content',
          value: contentPreview,
          isInline: false,
        ),
        EmbedFieldBuilder(
          name: 'Jump',
          value: '[Open Message]($jumpUrl)',
          isInline: false,
        ),
      ];

    await channel.sendMessage(MessageBuilder(embeds: <EmbedBuilder>[embed]));
  }

  Future<void> _onMessageDelete({
    required NyxxGateway client,
    required MessageDeleteEvent event,
  }) async {
    if (event.guildId == null) {
      return;
    }

    BotRuntimeComponents? components = runtimeProvider();
    if (components == null) {
      return;
    }

    PartialTextChannel? channel = _resolveLogChannel(
      client: client,
      channelId: components.config.logs.commLogChannelId,
    );
    if (channel == null) {
      return;
    }

    String channelMention = DiscordFormatters.channelMention(
      channelId: event.channelId.value,
    );
    String description =
        'Message ID: `${event.id.value}`\nChannel: $channelMention\nAuthor: unknown (Discord delete events do not include author data)';

    EmbedBuilder embed = components.embedFactory.base(title: 'Message Deleted')
      ..description = description;

    await channel.sendMessage(MessageBuilder(embeds: <EmbedBuilder>[embed]));
  }

  Future<void> _onMessageReactionAdd({
    required NyxxGateway client,
    required MessageReactionAddEvent event,
  }) async {
    if (event.guildId == null) {
      return;
    }

    Member? member = event.member;
    if (member == null) {
      return;
    }

    User? reactor = member.user;
    if (reactor == null || reactor.isBot) {
      return;
    }

    Emoji emoji = event.emoji;
    if (emoji is! TextEmoji) {
      return;
    }

    String reactionName = emoji.name;
    if (!ReactionUtils.isSupportedHeartEmoji(reactionName)) {
      return;
    }

    BotRuntimeComponents? components = runtimeProvider();
    if (components == null) {
      return;
    }

    int targetUserId = components.config.logs.heartTargetUserId;
    if (targetUserId <= 0) {
      return;
    }

    await _mirrorHeartReaction(event: event, targetUserId: targetUserId);
  }

  Future<void> _onGuildAuditLogCreate({
    required NyxxGateway client,
    required GuildAuditLogCreateEvent event,
  }) async {
    BotRuntimeComponents? components = runtimeProvider();
    if (components == null) {
      return;
    }

    PartialTextChannel? channel = _resolveLogChannel(
      client: client,
      channelId: components.config.logs.auditLogChannelId,
    );
    if (channel == null) {
      return;
    }

    AuditLogEntry entry = event.entry;

    if (entry.actionType == AuditLogEvent.memberKick) {
      String description =
          'Moderator: ${_mention(entry.userId)}\nTarget: ${_mention(entry.targetId)}\nReason: ${_defaultReason(entry.reason)}';

      EmbedBuilder embed = components.embedFactory.base(title: 'Member Kicked')
        ..description = description;

      await channel.sendMessage(MessageBuilder(embeds: <EmbedBuilder>[embed]));
      return;
    }

    if (entry.actionType == AuditLogEvent.memberBanAdd) {
      String description =
          'Moderator: ${_mention(entry.userId)}\nTarget: ${_mention(entry.targetId)}\nReason: ${_defaultReason(entry.reason)}';

      EmbedBuilder embed = components.embedFactory.base(title: 'Member Banned')
        ..description = description;

      await channel.sendMessage(MessageBuilder(embeds: <EmbedBuilder>[embed]));
      return;
    }

    if (entry.actionType == AuditLogEvent.memberUpdate) {
      AuditLogChange? timeoutChange = _findChange(
        changes: entry.changes,
        key: 'communication_disabled_until',
      );
      if (timeoutChange == null) {
        return;
      }

      Object? timeoutEnd = timeoutChange.newValue;
      String timeoutText = timeoutEnd == null
          ? 'timeout removed'
          : '$timeoutEnd';

      String description =
          'Moderator: ${_mention(entry.userId)}\nTarget: ${_mention(entry.targetId)}\nTimeout Until: $timeoutText\nReason: ${_defaultReason(entry.reason)}';

      EmbedBuilder embed = components.embedFactory.base(
        title: 'Member Timed Out',
      )..description = description;

      await channel.sendMessage(MessageBuilder(embeds: <EmbedBuilder>[embed]));
    }
  }

  AuditLogChange? _findChange({
    required List<AuditLogChange>? changes,
    required String key,
  }) {
    if (changes == null) {
      return null;
    }

    for (AuditLogChange change in changes) {
      if (change.key == key) {
        return change;
      }
    }

    return null;
  }

  Future<void> _mirrorHeartReaction({
    required MessageReactionAddEvent event,
    required int targetUserId,
  }) async {
    Snowflake? messageAuthorId = event.messageAuthorId;

    if (messageAuthorId != null && messageAuthorId.value != targetUserId) {
      return;
    }

    try {
      if (messageAuthorId == null) {
        Message fetched = await event.message.fetch();
        int authorId = fetched.author.id.value;
        if (authorId != targetUserId) {
          return;
        }
        await fetched.react(
          ReactionBuilder(name: ReactionUtils.heartEmoji, id: null),
        );
        return;
      }

      await event.message.react(
        ReactionBuilder(name: ReactionUtils.heartEmoji, id: null),
      );
    } on Object catch (error) {
      logger.fine(
        'Failed to add mirrored heart reaction in channel ${event.channelId.value} for message ${event.messageId.value}: $error',
      );
    }
  }

  PartialTextChannel? _resolveLogChannel({
    required NyxxGateway client,
    required int? channelId,
  }) {
    if (channelId == null || channelId <= 0) {
      return null;
    }

    Snowflake id = Snowflake(channelId);
    if (!client.channels.cache.containsKey(id)) {
      return null;
    }

    Object? cachedChannel = client.channels.cache[id];
    if (cachedChannel is TextChannel || cachedChannel is PartialTextChannel) {
      return client.channels[id] as PartialTextChannel;
    }

    return null;
  }

  String _defaultReason(String? reason) =>
      reason == null || reason.trim().isEmpty ? 'No reason provided' : reason;

  String _mention(Snowflake? userId) {
    if (userId == null || userId.value <= 0) {
      return '`unknown`';
    }
    return DiscordFormatters.userMention(userId: userId.value);
  }
}
