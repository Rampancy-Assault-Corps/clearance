import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:racbot_nyxx/src/config/config_exception.dart';
import 'package:racbot_nyxx/src/config/config_loader.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigLoader', () {
    test('creates template files and loads defaults with override token', () {
      Directory tempDir = Directory.systemTemp.createTempSync(
        'racbot-config-defaults-',
      );
      String configPath = p.join(tempDir.path, 'config', 'bot.toml');

      ConfigLoader loader = ConfigLoader(environment: <String, String>{});
      ConfigOverrides overrides = const ConfigOverrides(
        discordToken: 'token-from-override',
        ownerIds: null,
        dataDir: null,
      );

      var config = loader.load(configPath: configPath, overrides: overrides);

      expect(File(configPath).existsSync(), isTrue);
      expect(
        File(p.join(tempDir.path, 'config', 'bot.toml.example')).existsSync(),
        isTrue,
      );
      expect(config.runtime.discordToken, 'token-from-override');
      expect(config.features.pingEnabled, isTrue);
      expect(config.logs.heartTargetUserId, 173261518572486656);
      expect(config.logs.userLogChannelId, isNull);
      expect(config.storage.atomicWrites, isTrue);
    });

    test('token precedence is env over cli over file', () {
      Directory tempDir = Directory.systemTemp.createTempSync(
        'racbot-config-token-',
      );
      String configPath = p.join(tempDir.path, 'bot.toml');

      File(configPath).writeAsStringSync('''
[runtime]
discord_token = "file-token"
''');

      ConfigLoader envLoader = ConfigLoader(
        environment: <String, String>{'DISCORD_TOKEN': 'env-token'},
      );
      ConfigOverrides cliOverrides = const ConfigOverrides(
        discordToken: 'cli-token',
        ownerIds: null,
        dataDir: null,
      );
      var envConfig = envLoader.load(
        configPath: configPath,
        overrides: cliOverrides,
      );
      expect(envConfig.runtime.discordToken, 'env-token');

      ConfigLoader cliLoader = ConfigLoader(environment: <String, String>{});
      var cliConfig = cliLoader.load(
        configPath: configPath,
        overrides: cliOverrides,
      );
      expect(cliConfig.runtime.discordToken, 'cli-token');

      ConfigOverrides noOverrides = const ConfigOverrides(
        discordToken: null,
        ownerIds: null,
        dataDir: null,
      );
      var fileConfig = cliLoader.load(
        configPath: configPath,
        overrides: noOverrides,
      );
      expect(fileConfig.runtime.discordToken, 'file-token');
    });

    test('owner ids and data dir overrides are applied', () {
      Directory tempDir = Directory.systemTemp.createTempSync(
        'racbot-config-owner-',
      );
      String configPath = p.join(tempDir.path, 'bot.toml');

      File(configPath).writeAsStringSync('''
[storage]
data_dir = "./data-default"

[runtime]
discord_token = "file-token"
owner_ids = [1, "2"]
''');

      ConfigLoader loader = ConfigLoader(environment: <String, String>{});
      ConfigOverrides overrides = const ConfigOverrides(
        discordToken: null,
        ownerIds: '3, 4',
        dataDir: './custom-data',
      );

      var config = loader.load(configPath: configPath, overrides: overrides);

      expect(config.runtime.ownerIds, equals(<int>{3, 4}));
      expect(
        config.runtime.dataDirPath,
        p.normalize(p.absolute('./custom-data')),
      );
    });

    test('invalid color fails validation', () {
      Directory tempDir = Directory.systemTemp.createTempSync(
        'racbot-config-color-',
      );
      String configPath = p.join(tempDir.path, 'bot.toml');

      File(configPath).writeAsStringSync('''
[branding]
primary_color = "not-a-color"

[runtime]
discord_token = "file-token"
''');

      ConfigLoader loader = ConfigLoader(environment: <String, String>{});
      ConfigOverrides overrides = const ConfigOverrides(
        discordToken: null,
        ownerIds: null,
        dataDir: null,
      );

      expect(
        () => loader.load(configPath: configPath, overrides: overrides),
        throwsA(isA<ConfigException>()),
      );
    });

    test('missing token fails validation', () {
      Directory tempDir = Directory.systemTemp.createTempSync(
        'racbot-config-token-missing-',
      );
      String configPath = p.join(tempDir.path, 'bot.toml');

      File(configPath).writeAsStringSync('''
[runtime]
discord_token = ""
''');

      ConfigLoader loader = ConfigLoader(environment: <String, String>{});
      ConfigOverrides overrides = const ConfigOverrides(
        discordToken: null,
        ownerIds: null,
        dataDir: null,
      );

      expect(
        () => loader.load(configPath: configPath, overrides: overrides),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}
