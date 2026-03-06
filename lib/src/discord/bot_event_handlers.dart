import 'dart:async';

import 'package:nyxx/nyxx.dart';
import 'package:racbot_nyxx/src/model/bot_runtime_components.dart';
import 'package:racbot_nyxx/src/service/role_persistence_service.dart';
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

    await _restorePersistedRoles(
      client: client,
      components: components,
      event: event,
    );

    if (components.runnerRoleSyncService != null) {
      await components.runnerRoleSyncService!.assignRunnerRoleIfLinked(
        client: client,
        guildId: event.guildId,
        member: event.member,
      );
    }

    PartialTextChannel? channel = await _resolveLogChannel(
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

    _persistRemovedMemberRoles(components: components, event: event);

    PartialTextChannel? channel = await _resolveLogChannel(
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

  Future<void> _restorePersistedRoles({
    required NyxxGateway client,
    required BotRuntimeComponents components,
    required GuildMemberAddEvent event,
  }) async {
    User? user = event.member.user;
    if (user != null && user.isBot) {
      return;
    }

    PersistedRoleEntry? entry = components.rolePersistenceService.loadEntry(
      guildId: event.guildId.value,
      userId: event.member.id.value,
    );
    if (entry == null) {
      return;
    }

    Guild guild;
    try {
      guild = await client.guilds[event.guildId].fetch();
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to fetch guild ${event.guildId.value} while restoring persisted roles for member ${event.member.id.value}.',
        error,
        stackTrace,
      );
      return;
    }

    List<int> remainingRoleIds = <int>[];
    int restoredCount = 0;
    for (int roleId in entry.roleIds) {
      if (_memberHasRole(member: event.member, roleId: roleId)) {
        continue;
      }

      Role? role = _roleForId(guild: guild, roleId: roleId);
      if (role == null) {
        continue;
      }
      if (!_canRestoreRole(guild: guild, role: role)) {
        continue;
      }

      bool restored = await _restoreRole(
        client: client,
        guildId: event.guildId,
        memberId: event.member.id,
        roleId: role.id,
      );
      if (restored) {
        restoredCount += 1;
        continue;
      }

      remainingRoleIds.add(roleId);
    }

    if (remainingRoleIds.isEmpty) {
      components.rolePersistenceService.deleteEntry(
        guildId: event.guildId.value,
        userId: event.member.id.value,
      );
      if (restoredCount > 0) {
        logger.info(
          'Restored $restoredCount persisted roles for member ${event.member.id.value} in guild ${event.guildId.value}.',
        );
      }
      return;
    }

    components.rolePersistenceService.saveEntry(
      guildId: event.guildId.value,
      userId: event.member.id.value,
      roleIds: remainingRoleIds,
    );
    logger.warning(
      'Restored $restoredCount persisted roles for member ${event.member.id.value} in guild ${event.guildId.value}, but ${remainingRoleIds.length} role assignments still failed.',
    );
  }

  void _persistRemovedMemberRoles({
    required BotRuntimeComponents components,
    required GuildMemberRemoveEvent event,
  }) {
    if (event.user.isBot) {
      return;
    }

    Member? removedMember = event.removedMember;
    if (removedMember == null) {
      logger.fine(
        'Skipping role persistence for member ${event.user.id.value} in guild ${event.guildId.value} because the removed member was not cached.',
      );
      return;
    }

    List<int> roleIds = <int>[];
    for (Snowflake roleId in removedMember.roleIds) {
      int resolvedRoleId = roleId.value;
      if (resolvedRoleId <= 0 || resolvedRoleId == event.guildId.value) {
        continue;
      }
      roleIds.add(resolvedRoleId);
    }

    if (roleIds.isEmpty) {
      components.rolePersistenceService.deleteEntry(
        guildId: event.guildId.value,
        userId: event.user.id.value,
      );
      return;
    }

    components.rolePersistenceService.saveEntry(
      guildId: event.guildId.value,
      userId: event.user.id.value,
      roleIds: roleIds,
    );
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

    bool shouldLog = await _shouldLogMessageDelete(
      client: client,
      components: components,
      channelId: event.channelId,
    );
    if (!shouldLog) {
      logger.fine(
        'Ignored message delete ${event.id.value} in channel ${event.channelId.value} because it is outside the configured delete-log scope.',
      );
      return;
    }

    logger.info(
      'Caught message delete ${event.id.value} in channel ${event.channelId.value}.',
    );

    PartialTextChannel? channel = await _resolveLogChannel(
      client: client,
      channelId: components.config.logs.commLogChannelId,
    );
    if (channel == null) {
      logger.warning(
        'Caught message delete ${event.id.value}, but log channel ${components.config.logs.commLogChannelId} could not be resolved.',
      );
      return;
    }

    Message? deletedMessage = event.deletedMessage;
    MessageAuthor? deletedAuthor = deletedMessage?.author;
    if (deletedAuthor is User && deletedAuthor.isBot) {
      return;
    }

    String channelMention = DiscordFormatters.channelMention(
      channelId: event.channelId.value,
    );
    String authorText = _deletedAuthorText(message: deletedMessage);
    String contentPreview = _deletedContentPreview(message: deletedMessage);
    String sentAt = _deletedSentAtText(message: deletedMessage);
    EmbedAuthorBuilder? embedAuthor = _deletedEmbedAuthor(
      message: deletedMessage,
    );

    EmbedBuilder embed =
        components.embedFactory.base(title: 'MESSAGE DELETION CAPTURED')
          ..color = DiscordColor(0xFF3B30)
          ..author = embedAuthor
          ..description =
              'A message was removed from $channelMention.\nAuthor: $authorText'
          ..fields = <EmbedFieldBuilder>[
            EmbedFieldBuilder(
              name: 'Deleted Content',
              value: contentPreview,
              isInline: false,
            ),
            EmbedFieldBuilder(
              name: 'Message ID',
              value: '`${event.id.value}`',
              isInline: true,
            ),
            EmbedFieldBuilder(name: 'Sent At', value: sentAt, isInline: true),
          ];

    try {
      await channel.sendMessage(MessageBuilder(embeds: <EmbedBuilder>[embed]));
      logger.info(
        'Published delete log for message ${event.id.value} into channel ${channel.id.value}.',
      );
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to publish delete log for message ${event.id.value} into channel ${channel.id.value}.',
        error,
        stackTrace,
      );
    }
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

    PartialTextChannel? channel = await _resolveLogChannel(
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

  Future<PartialTextChannel?> _resolveLogChannel({
    required NyxxGateway client,
    required int? channelId,
  }) async {
    if (channelId == null || channelId <= 0) {
      return null;
    }

    Snowflake id = Snowflake(channelId);
    Object? cachedChannel = client.channels.cache[id];
    if (cachedChannel is TextChannel || cachedChannel is PartialTextChannel) {
      return client.channels[id] as PartialTextChannel;
    }

    try {
      Object fetchedChannel = await client.channels[id].fetch();
      if (fetchedChannel is TextChannel) {
        return client.channels[id] as PartialTextChannel;
      }
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to resolve log channel ${id.value}.',
        error,
        stackTrace,
      );
    }

    return null;
  }

  Future<bool> _shouldLogMessageDelete({
    required NyxxGateway client,
    required BotRuntimeComponents components,
    required Snowflake channelId,
  }) async {
    if (components.config.logs.commLogChannelId == null) {
      return false;
    }

    Set<int> configuredChannelIds =
        components.config.logs.commLogSourceChannelIds;
    if (configuredChannelIds.contains(channelId.value)) {
      return true;
    }

    Set<int> configuredCategoryIds = components.config.logs.commLogCategoryIds;
    if (configuredCategoryIds.isEmpty) {
      return false;
    }

    TextChannel? sourceChannel = await _fetchTextChannel(
      client: client,
      channelId: channelId,
    );
    if (sourceChannel == null) {
      return false;
    }

    int? resolvedCategoryId = await _resolveCategoryIdForChannel(
      client: client,
      channel: sourceChannel,
    );
    if (resolvedCategoryId == null) {
      return false;
    }

    return configuredCategoryIds.contains(resolvedCategoryId);
  }

  Future<TextChannel?> _fetchTextChannel({
    required NyxxGateway client,
    required Snowflake channelId,
  }) async {
    try {
      Object channel = await client.channels[channelId].fetch();
      if (channel is TextChannel) {
        return channel;
      }
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to fetch channel ${channelId.value} while evaluating delete-log scope.',
        error,
        stackTrace,
      );
    }
    return null;
  }

  Future<int?> _resolveCategoryIdForChannel({
    required NyxxGateway client,
    required TextChannel channel,
  }) async {
    if (channel is! GuildChannel) {
      return null;
    }

    GuildChannel guildChannel = channel as GuildChannel;
    Snowflake? parentId = guildChannel.parentId;
    if (parentId == null) {
      return null;
    }

    Object? cachedParent = client.channels.cache[parentId];
    if (cachedParent is GuildCategory) {
      return cachedParent.id.value;
    }
    if (cachedParent is GuildChannel && cachedParent.parentId != null) {
      return cachedParent.parentId!.value;
    }

    try {
      Object fetchedParent = await client.channels[parentId].fetch();
      if (fetchedParent is GuildCategory) {
        return fetchedParent.id.value;
      }
      if (fetchedParent is GuildChannel && fetchedParent.parentId != null) {
        return fetchedParent.parentId!.value;
      }
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to fetch parent channel ${parentId.value} while evaluating delete-log scope.',
        error,
        stackTrace,
      );
    }

    return null;
  }

  bool _memberHasRole({required Member member, required int roleId}) {
    for (Snowflake existingRoleId in member.roleIds) {
      if (existingRoleId.value == roleId) {
        return true;
      }
    }
    return false;
  }

  bool _canRestoreRole({required Guild guild, required Role role}) {
    if (role.id.value == guild.id.value) {
      return false;
    }
    if (role.tags != null) {
      return false;
    }
    return true;
  }

  Role? _roleForId({required Guild guild, required int roleId}) {
    for (Role role in guild.roleList) {
      if (role.id.value == roleId) {
        return role;
      }
    }
    return null;
  }

  Future<bool> _restoreRole({
    required NyxxGateway client,
    required Snowflake guildId,
    required Snowflake memberId,
    required Snowflake roleId,
  }) async {
    try {
      await client.guilds[guildId].members[memberId].addRole(
        roleId,
        auditLogReason: 'Restoring persisted member roles',
      );
      return true;
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to restore role ${roleId.value} for member ${memberId.value} in guild ${guildId.value}.',
        error,
        stackTrace,
      );
      return false;
    }
  }

  String _deletedAuthorText({required Message? message}) {
    MessageAuthor? author = message?.author;
    if (author == null) {
      return 'unknown';
    }
    return DiscordFormatters.userMention(userId: author.id.value);
  }

  EmbedAuthorBuilder? _deletedEmbedAuthor({required Message? message}) {
    MessageAuthor? author = message?.author;
    if (author is! User) {
      return null;
    }

    String displayName = author.globalName ?? author.username;
    return EmbedAuthorBuilder(name: displayName, iconUrl: author.avatar.url);
  }

  String _deletedContentPreview({required Message? message}) {
    String content = message?.content ?? '';
    if (content.trim().isNotEmpty) {
      return TextUtils.truncate(value: content, maxLength: maxContentPreview);
    }

    int attachmentCount = message?.attachments.length ?? 0;
    if (attachmentCount > 0) {
      return '[No text content. Attachments: $attachmentCount]';
    }

    return '[Content unavailable. Discord did not provide a cached message.]';
  }

  String _deletedSentAtText({required Message? message}) {
    DateTime? timestamp = message?.timestamp;
    if (timestamp == null) {
      return 'unknown';
    }
    return timestamp.toUtc().toIso8601String();
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
