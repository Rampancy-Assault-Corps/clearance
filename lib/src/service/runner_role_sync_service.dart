import 'package:nyxx/nyxx.dart';
import 'package:racbot_nyxx/src/service/firebase_account_link_repository.dart';
import 'package:racbot_nyxx/src/util/app_logger.dart';

class RunnerRoleSyncService {
  static const Duration syncInterval = Duration(seconds: 10);
  static const Duration _fallbackSnapshotInterval = Duration(seconds: 30);
  static const Duration _safetySnapshotInterval = Duration(minutes: 15);

  final int runnerRoleId;
  final FirebaseAccountLinkRepository repository;
  final AppLogger logger;

  Set<int> _lastLinkedDiscordIds = <int>{};
  int _lastSequence = 0;
  int _lastFullSnapshotAt = 0;
  bool _hasLoadedSnapshot = false;
  bool _syncInFlight = false;

  RunnerRoleSyncService({
    required this.runnerRoleId,
    required this.repository,
    required this.logger,
  });

  Future<void> syncAllGuilds({
    required NyxxGateway client,
    bool force = false,
  }) async {
    if (_syncInFlight) {
      logger.fine(
        'Runner role sync skipped because another sync is in progress.',
      );
      return;
    }

    _syncInFlight = true;
    try {
      if (force || !_hasLoadedSnapshot) {
        await _runFullSync(client: client);
        return;
      }

      LinkedDiscordDelta delta = await repository.loadLinkedDiscordDelta(
        afterSequence: _lastSequence,
      );
      if (!delta.loaded) {
        logger.warning(
          'Runner role sync skipped because linked account data could not be loaded.',
        );
        return;
      }

      int now = DateTime.now().millisecondsSinceEpoch;
      bool changeFeedAvailable = delta.latestSequence > 0 || _lastSequence > 0;
      if (_shouldRunFallbackSnapshot(
        now: now,
        changeFeedAvailable: changeFeedAvailable,
      )) {
        await _runFullSync(client: client);
        return;
      }

      if (delta.changes.isEmpty) {
        _lastSequence = delta.latestSequence;
        logger.fine(
          'Runner role sync skipped because no Firestore link changes were detected.',
        );
        return;
      }

      Set<int> nextLinkedDiscordIds = Set<int>.from(_lastLinkedDiscordIds);
      for (LinkedDiscordChange change in delta.changes) {
        _applyChange(linkedDiscordIds: nextLinkedDiscordIds, change: change);
      }

      if (_sameIds(_lastLinkedDiscordIds, nextLinkedDiscordIds)) {
        _lastSequence = delta.latestSequence;
        logger.fine(
          'Runner role sync skipped because Firestore changes did not affect linked Discord IDs.',
        );
        return;
      }

      await _syncGuildDelta(
        client: client,
        previousLinkedDiscordIds: _lastLinkedDiscordIds,
        nextLinkedDiscordIds: nextLinkedDiscordIds,
      );
      _lastLinkedDiscordIds = nextLinkedDiscordIds;
      _lastSequence = delta.latestSequence;
      _hasLoadedSnapshot = true;
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> assignRunnerRoleIfLinked({
    required NyxxGateway client,
    required Snowflake guildId,
    required Member member,
  }) async {
    User? user = member.user;
    if (user != null && user.isBot) {
      return;
    }

    if (!_hasLoadedSnapshot) {
      LinkedDiscordSnapshot snapshot = await repository.loadLinkedDiscordIds();
      if (!snapshot.loaded) {
        return;
      }
      _lastLinkedDiscordIds = Set<int>.from(snapshot.discordIds);
      _lastSequence = snapshot.latestSequence;
      _hasLoadedSnapshot = true;
    }

    if (!_lastLinkedDiscordIds.contains(member.id.value)) {
      return;
    }

    Snowflake roleId = Snowflake(runnerRoleId);
    if (member.roleIds.contains(roleId)) {
      return;
    }

    await _addRole(
      client: client,
      guildId: guildId,
      memberId: member.id,
      roleId: roleId,
    );
  }

  Future<void> dispose() => repository.close();

  Future<void> _runFullSync({required NyxxGateway client}) async {
    LinkedDiscordSnapshot snapshot = await repository.loadLinkedDiscordIds();
    if (!snapshot.loaded) {
      logger.warning(
        'Runner role sync skipped because linked account data could not be loaded.',
      );
      return;
    }

    Set<int> linkedDiscordIds = snapshot.discordIds;
    if (_hasLoadedSnapshot &&
        _sameIds(_lastLinkedDiscordIds, linkedDiscordIds)) {
      _lastSequence = snapshot.latestSequence;
      logger.fine(
        'Runner role sync skipped because linked Discord IDs are unchanged.',
      );
      return;
    }

    Snowflake roleId = Snowflake(runnerRoleId);
    List<Snowflake> guildIds = await _guildIds(client: client);
    if (guildIds.isEmpty) {
      logger.warning(
        'Runner role sync skipped because no guilds are available.',
      );
      return;
    }

    for (Snowflake guildId in guildIds) {
      await _syncGuild(
        client: client,
        guildId: guildId,
        roleId: roleId,
        linkedDiscordIds: linkedDiscordIds,
      );
    }

    _lastLinkedDiscordIds = Set<int>.from(linkedDiscordIds);
    _lastSequence = snapshot.latestSequence;
    _lastFullSnapshotAt = DateTime.now().millisecondsSinceEpoch;
    _hasLoadedSnapshot = true;
  }

  void _applyChange({
    required Set<int> linkedDiscordIds,
    required LinkedDiscordChange change,
  }) {
    int? previousDiscordId = change.previousDiscordId;
    if (change.previousRunnerEligible &&
        previousDiscordId != null &&
        previousDiscordId > 0) {
      linkedDiscordIds.remove(previousDiscordId);
    }

    int? discordId = change.discordId;
    if (change.runnerEligible && discordId != null && discordId > 0) {
      linkedDiscordIds.add(discordId);
    }
  }

  bool _sameIds(Set<int> left, Set<int> right) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (int id in left) {
      if (!right.contains(id)) {
        return false;
      }
    }
    return true;
  }

  bool _shouldRunFallbackSnapshot({
    required int now,
    required bool changeFeedAvailable,
  }) {
    int interval = changeFeedAvailable
        ? _safetySnapshotInterval.inMilliseconds
        : _fallbackSnapshotInterval.inMilliseconds;
    if (_lastFullSnapshotAt == 0) {
      return true;
    }
    return now - _lastFullSnapshotAt >= interval;
  }

  Future<List<Snowflake>> _guildIds({required NyxxGateway client}) async {
    Set<Snowflake> guildIds = client.guilds.cache.values
        .whereType<Guild>()
        .map((Guild guild) => guild.id)
        .toSet();
    if (guildIds.isNotEmpty) {
      return guildIds.toList();
    }

    Snowflake? after;
    while (true) {
      List<UserGuild> page;
      try {
        page = await client.listGuilds(limit: 200, after: after);
      } on Object catch (error, stackTrace) {
        logger.severe(
          'Failed to list guilds for runner role sync.',
          error,
          stackTrace,
        );
        return guildIds.toList();
      }

      if (page.isEmpty) {
        return guildIds.toList();
      }

      for (UserGuild guild in page) {
        guildIds.add(guild.id);
      }

      after = page.last.id;
      if (page.length < 200) {
        return guildIds.toList();
      }
    }
  }

  Future<void> _syncGuildDelta({
    required NyxxGateway client,
    required Set<int> previousLinkedDiscordIds,
    required Set<int> nextLinkedDiscordIds,
  }) async {
    Set<int> addIds = nextLinkedDiscordIds.difference(previousLinkedDiscordIds);
    Set<int> removeIds = previousLinkedDiscordIds.difference(
      nextLinkedDiscordIds,
    );
    if (addIds.isEmpty && removeIds.isEmpty) {
      return;
    }

    Snowflake roleId = Snowflake(runnerRoleId);
    List<Snowflake> guildIds = await _guildIds(client: client);
    if (guildIds.isEmpty) {
      logger.warning(
        'Runner role delta sync skipped because no guilds are available.',
      );
      return;
    }

    for (Snowflake guildId in guildIds) {
      await _syncGuildDeltaMembers(
        client: client,
        guildId: guildId,
        roleId: roleId,
        addIds: addIds,
        removeIds: removeIds,
      );
    }
  }

  Future<void> _syncGuildDeltaMembers({
    required NyxxGateway client,
    required Snowflake guildId,
    required Snowflake roleId,
    required Set<int> addIds,
    required Set<int> removeIds,
  }) async {
    Guild guild;
    try {
      guild = await client.guilds[guildId].fetch();
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to fetch guild ${guildId.value} before runner role delta sync.',
        error,
        stackTrace,
      );
      return;
    }

    bool runnerRoleExists = guild.roleList.any(
      (Role role) => role.id == roleId,
    );
    if (!runnerRoleExists) {
      logger.warning(
        'Runner role ${roleId.value} does not exist in guild ${guildId.value}.',
      );
      return;
    }

    int addedCount = 0;
    int removedCount = 0;

    for (int memberIdValue in addIds) {
      bool added = await _addRoleIfNeeded(
        client: client,
        guildId: guildId,
        memberId: Snowflake(memberIdValue),
        roleId: roleId,
      );
      if (added) {
        addedCount += 1;
      }
    }

    for (int memberIdValue in removeIds) {
      bool removed = await _removeRoleIfNeeded(
        client: client,
        guildId: guildId,
        memberId: Snowflake(memberIdValue),
        roleId: roleId,
      );
      if (removed) {
        removedCount += 1;
      }
    }

    logger.info(
      'Runner role delta sync finished for guild ${guildId.value}: addCandidates=${addIds.length} removeCandidates=${removeIds.length} added=$addedCount removed=$removedCount.',
    );
  }

  Future<void> _syncGuild({
    required NyxxGateway client,
    required Snowflake guildId,
    required Snowflake roleId,
    required Set<int> linkedDiscordIds,
  }) async {
    Guild guild;
    try {
      guild = await client.guilds[guildId].fetch();
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to fetch guild ${guildId.value} before runner role sync.',
        error,
        stackTrace,
      );
      return;
    }

    bool runnerRoleExists = guild.roleList.any(
      (Role role) => role.id == roleId,
    );
    if (!runnerRoleExists) {
      logger.warning(
        'Runner role ${roleId.value} does not exist in guild ${guildId.value}.',
      );
      return;
    }

    List<Member> members = await _listAllMembers(
      client: client,
      guildId: guildId,
    );
    int addedCount = 0;
    int removedCount = 0;

    for (Member member in members) {
      User? user = member.user;
      if (user != null && user.isBot) {
        continue;
      }

      bool shouldHaveRole = linkedDiscordIds.contains(member.id.value);
      bool hasRole = member.roleIds.contains(roleId);

      if (shouldHaveRole && !hasRole) {
        bool added = await _addRole(
          client: client,
          guildId: guildId,
          memberId: member.id,
          roleId: roleId,
        );
        if (added) {
          addedCount += 1;
        }
        continue;
      }

      if (!shouldHaveRole && hasRole) {
        bool removed = await _removeRole(
          client: client,
          guildId: guildId,
          memberId: member.id,
          roleId: roleId,
        );
        if (removed) {
          removedCount += 1;
        }
      }
    }

    logger.info(
      'Runner role sync finished for guild ${guildId.value}: scanned=${members.length} added=$addedCount removed=$removedCount.',
    );
  }

  Future<List<Member>> _listAllMembers({
    required NyxxGateway client,
    required Snowflake guildId,
  }) async {
    List<Member> members = <Member>[];
    Snowflake? after;

    while (true) {
      List<Member> page;
      try {
        page = await client.guilds[guildId].members.list(
          limit: 1000,
          after: after,
        );
      } on Object catch (error, stackTrace) {
        logger.severe(
          'Failed to list members for guild ${guildId.value}.',
          error,
          stackTrace,
        );
        return members;
      }

      if (page.isEmpty) {
        return members;
      }

      members.addAll(page);
      after = page.last.id;
      if (page.length < 1000) {
        return members;
      }
    }
  }

  Future<bool> _addRoleIfNeeded({
    required NyxxGateway client,
    required Snowflake guildId,
    required Snowflake memberId,
    required Snowflake roleId,
  }) async {
    Member? member = await _fetchMember(
      client: client,
      guildId: guildId,
      memberId: memberId,
    );
    if (member == null) {
      return false;
    }

    User? user = member.user;
    if (user != null && user.isBot) {
      return false;
    }

    if (member.roleIds.contains(roleId)) {
      return false;
    }

    return _addRole(
      client: client,
      guildId: guildId,
      memberId: memberId,
      roleId: roleId,
    );
  }

  Future<bool> _removeRoleIfNeeded({
    required NyxxGateway client,
    required Snowflake guildId,
    required Snowflake memberId,
    required Snowflake roleId,
  }) async {
    Member? member = await _fetchMember(
      client: client,
      guildId: guildId,
      memberId: memberId,
    );
    if (member == null) {
      return false;
    }

    if (!member.roleIds.contains(roleId)) {
      return false;
    }

    return _removeRole(
      client: client,
      guildId: guildId,
      memberId: memberId,
      roleId: roleId,
    );
  }

  Future<Member?> _fetchMember({
    required NyxxGateway client,
    required Snowflake guildId,
    required Snowflake memberId,
  }) async {
    try {
      return await client.guilds[guildId].members[memberId].fetch();
    } on Object catch (error, stackTrace) {
      String message = error.toString().toLowerCase();
      if (message.contains('404') ||
          message.contains('unknown member') ||
          message.contains('not found')) {
        logger.fine(
          'Runner role sync skipped member ${memberId.value} in guild ${guildId.value} because the member is not currently present.',
        );
        return null;
      }

      logger.severe(
        'Failed to fetch member ${memberId.value} in guild ${guildId.value}.',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<bool> _addRole({
    required NyxxGateway client,
    required Snowflake guildId,
    required Snowflake memberId,
    required Snowflake roleId,
  }) async {
    try {
      await client.guilds[guildId].members[memberId].addRole(
        roleId,
        auditLogReason: 'Linked RAC account verified in Firestore',
      );
      logger.info(
        'Assigned runner role to member ${memberId.value} in guild ${guildId.value}.',
      );
      return true;
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to assign runner role to member ${memberId.value} in guild ${guildId.value}.',
        error,
        stackTrace,
      );
      return false;
    }
  }

  Future<bool> _removeRole({
    required NyxxGateway client,
    required Snowflake guildId,
    required Snowflake memberId,
    required Snowflake roleId,
  }) async {
    try {
      await client.guilds[guildId].members[memberId].removeRole(
        roleId,
        auditLogReason: 'Linked RAC account missing from Firestore',
      );
      logger.info(
        'Removed runner role from member ${memberId.value} in guild ${guildId.value}.',
      );
      return true;
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to remove runner role from member ${memberId.value} in guild ${guildId.value}.',
        error,
        stackTrace,
      );
      return false;
    }
  }
}
