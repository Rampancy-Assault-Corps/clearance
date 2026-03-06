import 'dart:convert';
import 'dart:io';

import 'package:googleapis/firestore/v1.dart' as firestore;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:racbot_nyxx/src/util/app_logger.dart';

class LinkedDiscordSnapshot {
  final bool loaded;
  final Set<int> discordIds;
  final int latestSequence;

  const LinkedDiscordSnapshot({
    required this.loaded,
    required this.discordIds,
    required this.latestSequence,
  });
}

class LinkedDiscordChange {
  final int sequence;
  final int? previousDiscordId;
  final int? discordId;
  final bool previousRunnerEligible;
  final bool runnerEligible;

  const LinkedDiscordChange({
    required this.sequence,
    required this.previousDiscordId,
    required this.discordId,
    required this.previousRunnerEligible,
    required this.runnerEligible,
  });
}

class LinkedDiscordDelta {
  final bool loaded;
  final int latestSequence;
  final List<LinkedDiscordChange> changes;

  const LinkedDiscordDelta({
    required this.loaded,
    required this.latestSequence,
    required this.changes,
  });
}

class FirebaseAccountLinkRepository {
  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/datastore',
  ];
  static const String _accountLinksCollection = 'account_links';
  static const String _linkSyncEventsCollection = 'link_sync_events';
  static const String _linkSyncStateCollection = 'link_sync_state';

  final String serviceAccountPath;
  final AppLogger logger;

  AutoRefreshingAuthClient? _authClient;
  firestore.FirestoreApi? _firestoreApi;
  String? _projectId;
  bool _missingCredentialNoticeShown = false;

  FirebaseAccountLinkRepository({
    required this.serviceAccountPath,
    required this.logger,
  });

  Future<LinkedDiscordSnapshot> loadLinkedDiscordIds() async {
    firestore.FirestoreApi? api = await _api();
    String? projectId = _projectId;
    if (api == null || projectId == null || projectId.isEmpty) {
      return const LinkedDiscordSnapshot(
        loaded: false,
        discordIds: <int>{},
        latestSequence: 0,
      );
    }

    Set<int> linkedDiscordIds = <int>{};
    String? nextPageToken;
    int scannedDocuments = 0;
    int latestSequence = await _loadLatestSequence(api: api);

    do {
      firestore.ListDocumentsResponse response;
      try {
        response = await api.projects.databases.documents.list(
          _documentsRoot(projectId),
          _accountLinksCollection,
          pageSize: 300,
          pageToken: nextPageToken,
          mask_fieldPaths: <String>['bungieConnected', 'discordId'],
        );
      } on Object catch (error, stackTrace) {
        logger.severe(
          'Failed to fetch account link documents from Firestore.',
          error,
          stackTrace,
        );
        return const LinkedDiscordSnapshot(
          loaded: false,
          discordIds: <int>{},
          latestSequence: 0,
        );
      }

      List<firestore.Document> documents =
          response.documents ?? <firestore.Document>[];
      scannedDocuments += documents.length;

      for (firestore.Document document in documents) {
        bool bungieConnected = _boolField(
          document: document,
          key: 'bungieConnected',
        );
        int? discordId = _intField(document: document, key: 'discordId');
        if (!bungieConnected || discordId == null || discordId <= 0) {
          continue;
        }
        linkedDiscordIds.add(discordId);
      }

      nextPageToken = response.nextPageToken;
    } while (nextPageToken != null && nextPageToken.isNotEmpty);

    logger.info(
      'Loaded ${linkedDiscordIds.length} linked Discord IDs from $scannedDocuments Firestore account link documents.',
    );
    return LinkedDiscordSnapshot(
      loaded: true,
      discordIds: linkedDiscordIds,
      latestSequence: latestSequence,
    );
  }

  Future<LinkedDiscordDelta> loadLinkedDiscordDelta({
    required int afterSequence,
  }) async {
    firestore.FirestoreApi? api = await _api();
    String? projectId = _projectId;
    if (api == null || projectId == null || projectId.isEmpty) {
      return const LinkedDiscordDelta(
        loaded: false,
        latestSequence: 0,
        changes: <LinkedDiscordChange>[],
      );
    }

    int latestSequence = await _loadLatestSequence(api: api);
    if (latestSequence <= afterSequence) {
      return LinkedDiscordDelta(
        loaded: true,
        latestSequence: latestSequence,
        changes: const <LinkedDiscordChange>[],
      );
    }

    List<LinkedDiscordChange> changes = <LinkedDiscordChange>[];
    int cursor = afterSequence;

    while (cursor < latestSequence) {
      List<LinkedDiscordChange> page = await _loadLinkSyncEventPage(
        api: api,
        afterSequence: cursor,
      );
      if (page.isEmpty) {
        logger.warning(
          'Runner role sync change page was empty before reaching the latest Firestore sequence. Retrying next cycle.',
        );
        return LinkedDiscordDelta(
          loaded: true,
          latestSequence: cursor,
          changes: changes,
        );
      }

      for (LinkedDiscordChange change in page) {
        changes.add(change);
        cursor = change.sequence;
      }
    }

    logger.info(
      'Loaded ${changes.length} Firestore link sync event(s) after sequence $afterSequence.',
    );
    return LinkedDiscordDelta(
      loaded: true,
      latestSequence: cursor,
      changes: changes,
    );
  }

  Future<void> close() async {
    _firestoreApi = null;
    _projectId = null;
    _authClient?.close();
    _authClient = null;
  }

  Future<firestore.FirestoreApi?> _api() async {
    AutoRefreshingAuthClient? client = await _client();
    String? projectId = _projectId;
    if (client == null || projectId == null || projectId.isEmpty) {
      return null;
    }

    firestore.FirestoreApi? api = _firestoreApi;
    if (api != null) {
      return api;
    }

    firestore.FirestoreApi nextApi = firestore.FirestoreApi(client);
    _firestoreApi = nextApi;
    return nextApi;
  }

  Future<AutoRefreshingAuthClient?> _client() async {
    if (_authClient != null && _projectId != null && _projectId!.isNotEmpty) {
      return _authClient;
    }

    File credentialFile = File(serviceAccountPath);
    if (!credentialFile.existsSync()) {
      if (!_missingCredentialNoticeShown) {
        logger.warning(
          'Runner role sync is enabled but no service account file exists at $serviceAccountPath.',
        );
        _missingCredentialNoticeShown = true;
      }
      return null;
    }

    String credentialsJson;
    try {
      credentialsJson = await credentialFile.readAsString();
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to read the service account file at $serviceAccountPath.',
        error,
        stackTrace,
      );
      return null;
    }

    Map<String, dynamic> credentialMap;
    try {
      credentialMap = jsonDecode(credentialsJson) as Map<String, dynamic>;
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to decode the service account JSON at $serviceAccountPath.',
        error,
        stackTrace,
      );
      return null;
    }

    String? projectId = credentialMap['project_id'] as String?;
    if (projectId == null || projectId.trim().isEmpty) {
      logger.severe(
        'The service account JSON at $serviceAccountPath does not contain project_id.',
      );
      return null;
    }

    try {
      ServiceAccountCredentials credentials =
          ServiceAccountCredentials.fromJson(credentialsJson);
      AutoRefreshingAuthClient authClient = await clientViaServiceAccount(
        credentials,
        _scopes,
        baseClient: http.Client(),
      );
      _projectId = projectId.trim();
      _authClient = authClient;
      _missingCredentialNoticeShown = false;
      return _authClient;
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to initialize the Firestore auth client for runner role sync.',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<int> _loadLatestSequence({required firestore.FirestoreApi api}) async {
    String projectId = _projectId!;
    firestore.ListDocumentsResponse response;
    try {
      response = await api.projects.databases.documents.list(
        _documentsRoot(projectId),
        _linkSyncStateCollection,
        pageSize: 1,
        mask_fieldPaths: <String>['latestSequence'],
      );
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to load the Firestore runner sync cursor document.',
        error,
        stackTrace,
      );
      return 0;
    }

    List<firestore.Document> documents =
        response.documents ?? <firestore.Document>[];
    if (documents.isEmpty) {
      return 0;
    }

    return _intField(document: documents.first, key: 'latestSequence') ?? 0;
  }

  Future<List<LinkedDiscordChange>> _loadLinkSyncEventPage({
    required firestore.FirestoreApi api,
    required int afterSequence,
  }) async {
    String projectId = _projectId!;
    firestore.RunQueryRequest request = firestore.RunQueryRequest(
      structuredQuery: firestore.StructuredQuery(
        from: <firestore.CollectionSelector>[
          firestore.CollectionSelector(collectionId: _linkSyncEventsCollection),
        ],
        where: firestore.Filter(
          fieldFilter: firestore.FieldFilter(
            field: firestore.FieldReference(fieldPath: 'sequence'),
            op: 'GREATER_THAN',
            value: firestore.Value(integerValue: '$afterSequence'),
          ),
        ),
        orderBy: <firestore.Order>[
          firestore.Order(
            field: firestore.FieldReference(fieldPath: 'sequence'),
            direction: 'ASCENDING',
          ),
        ],
        limit: 100,
      ),
    );

    firestore.RunQueryResponse response;
    try {
      response = await api.projects.databases.documents.runQuery(
        request,
        _documentsRoot(projectId),
      );
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to query Firestore link sync events.',
        error,
        stackTrace,
      );
      return <LinkedDiscordChange>[];
    }

    List<LinkedDiscordChange> changes = <LinkedDiscordChange>[];
    for (firestore.RunQueryResponseElement element in response) {
      firestore.Document? document = element.document;
      if (document == null) {
        continue;
      }

      int? sequence = _intField(document: document, key: 'sequence');
      if (sequence == null || sequence <= afterSequence) {
        continue;
      }

      changes.add(
        LinkedDiscordChange(
          sequence: sequence,
          previousDiscordId: _intField(
            document: document,
            key: 'previousDiscordId',
          ),
          discordId: _intField(document: document, key: 'discordId'),
          previousRunnerEligible: _boolField(
            document: document,
            key: 'previousRunnerEligible',
          ),
          runnerEligible: _boolField(document: document, key: 'runnerEligible'),
        ),
      );
    }

    return changes;
  }

  String _documentsRoot(String projectId) =>
      'projects/$projectId/databases/(default)/documents';

  bool _boolField({required firestore.Document document, required String key}) {
    firestore.Value? value = document.fields?[key];
    return value?.booleanValue ?? false;
  }

  int? _intField({required firestore.Document document, required String key}) {
    firestore.Value? value = document.fields?[key];
    String? integerValue = value?.integerValue;
    if (integerValue != null && integerValue.isNotEmpty) {
      return int.tryParse(integerValue);
    }

    String? stringValue = value?.stringValue;
    if (stringValue != null && stringValue.isNotEmpty) {
      return int.tryParse(stringValue);
    }

    return null;
  }
}
