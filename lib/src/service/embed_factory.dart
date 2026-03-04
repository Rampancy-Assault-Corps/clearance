import 'package:nyxx/nyxx.dart';
import 'package:racbot_nyxx/src/config/bot_config.dart';
import 'package:racbot_nyxx/src/util/color_parser.dart';

class EmbedFactory {
  final BotConfig config;

  const EmbedFactory({required this.config});

  EmbedBuilder base({required String title}) {
    Uri? avatarUri = Uri.tryParse(config.branding.avatarUrl);
    EmbedFooterBuilder footer = EmbedFooterBuilder(
      text: config.branding.companyName,
      iconUrl: avatarUri,
    );

    return EmbedBuilder(
      title: title,
      color: ColorParser.parseHex(config.branding.primaryColorHex),
      footer: footer,
      timestamp: DateTime.now().toUtc(),
    );
  }

  EmbedBuilder info({required String title, required String description}) =>
      base(title: title)..description = description;

  EmbedBuilder error({required String title, required String description}) =>
      base(title: title)..description = ':warning: $description';
}
