import '../game/classic_hareeg_match_snapshot.dart';
import '../game/classic_hareeg_round.dart';
import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';
import '../rules/match_progression_rules.dart';
import 'classic_hareeg_match_report.dart';

/// Match-report schema version implemented by this file.
const int matchReportV1Version = 1;

/// Decodes a v1-format match report.
ClassicHareegMatchReport decodeMatchReportV1(Map<String, Object?> json) {
  final version = asJsonInt(json['version']);
  if (version != matchReportV1Version) {
    throw const FormatException('Unsupported match report version.');
  }

  final appJson = asJsonMap(json['app']);
  final platform = asJsonString(json['platform']);
  final generatedAtRaw = asJsonString(json['generatedAt']);
  final generatedAt = generatedAtRaw == null
      ? null
      : DateTime.tryParse(generatedAtRaw);
  final stage = MatchReportStage.fromName(asJsonString(json['stage']));
  final setupJson = asJsonMap(json['setup']);
  final roundNumber = asJsonInt(json['roundNumber']);
  final currentSeat = PlayerSeat.fromName(asJsonString(json['currentSeat']));
  final turnPhase = TurnPhase.fromName(asJsonString(json['turnPhase']));
  final scoresJson = asJsonMap(json['scores']);
  final snapshotJson = asJsonMap(json['snapshot']);

  if (appJson == null ||
      platform == null ||
      generatedAt == null ||
      stage == null ||
      setupJson == null ||
      roundNumber == null ||
      roundNumber <= 0 ||
      currentSeat == null ||
      turnPhase == null ||
      scoresJson == null ||
      snapshotJson == null) {
    throw const FormatException('Invalid match report.');
  }

  final roundResultJson = asJsonMap(json['roundResult']);
  final matchProgressJson = asJsonMap(json['matchProgress']);

  return ClassicHareegMatchReport(
    app: _appMetadataFromJson(appJson),
    platform: platform,
    generatedAt: generatedAt,
    stage: stage,
    setup: ClassicHareegSetup.fromJson(setupJson),
    seed: asJsonInt(json['seed']),
    roundNumber: roundNumber,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    scores: _scoresFromJson(scoresJson),
    snapshot: ClassicHareegMatchSnapshot.fromJson(snapshotJson),
    roundResult: roundResultJson == null
        ? null
        : _roundResultFromJson(roundResultJson),
    matchProgress: matchProgressJson == null
        ? null
        : _matchProgressFromJson(matchProgressJson),
  );
}

/// Encodes [report] into a v1-format match report.
Map<String, Object?> encodeMatchReportV1(ClassicHareegMatchReport report) {
  return {
    'version': matchReportV1Version,
    'schema': 'classic_hareeg_match_report',
    'app': _appMetadataToJson(report.app),
    'platform': report.platform,
    'generatedAt': report.generatedAt.toUtc().toIso8601String(),
    'stage': report.stage.name,
    'setup': report.setup.toJson(),
    'seed': report.seed,
    'roundNumber': report.roundNumber,
    'currentSeat': report.currentSeat.name,
    'turnPhase': report.turnPhase.name,
    'scores': {
      for (final entry in report.scores.entries) entry.key.name: entry.value,
    },
    'snapshot': report.snapshot.toJson(),
    if (report.roundResult != null)
      'roundResult': _roundResultToJson(report.roundResult!),
    if (report.matchProgress != null)
      'matchProgress': _matchProgressToJson(report.matchProgress!),
  };
}

MatchReportAppMetadata _appMetadataFromJson(Map<String, Object?> json) {
  final appId = asJsonString(json['appId']);
  final appName = asJsonString(json['appName']);
  final version = asJsonString(json['version']);
  final buildNumber = asJsonString(json['buildNumber']);
  if (appId == null ||
      appName == null ||
      version == null ||
      buildNumber == null) {
    throw const FormatException('Invalid match report app metadata.');
  }
  return MatchReportAppMetadata(
    appId: appId,
    appName: appName,
    version: version,
    buildNumber: buildNumber,
  );
}

Map<String, Object?> _appMetadataToJson(MatchReportAppMetadata app) {
  return {
    'appId': app.appId,
    'appName': app.appName,
    'version': app.version,
    'buildNumber': app.buildNumber,
  };
}

RoundProgressResult _roundResultFromJson(Map<String, Object?> json) {
  final type = _roundOutcomeTypeFromName(asJsonString(json['type']));
  final remainingCardCounts = asJsonMap(json['remainingCardCounts']);
  if (type == null || remainingCardCounts == null) {
    throw const FormatException('Invalid match report round result.');
  }
  return RoundProgressResult(
    type: type,
    winner: PlayerSeat.fromName(asJsonString(json['winner'])),
    fiftyDiscarder: PlayerSeat.fromName(asJsonString(json['fiftyDiscarder'])),
    firstRoundFiftyException:
        asJsonBool(json['firstRoundFiftyException']) ?? false,
    remainingCardCounts: _scoresFromJson(remainingCardCounts),
  );
}

Map<String, Object?> _roundResultToJson(RoundProgressResult result) {
  return {
    'type': result.type.name,
    'winner': result.winner?.name,
    'fiftyDiscarder': result.fiftyDiscarder?.name,
    'firstRoundFiftyException': result.firstRoundFiftyException,
    'remainingCardCounts': {
      for (final entry in result.remainingCardCounts.entries)
        entry.key.name: entry.value,
    },
  };
}

MatchProgressState _matchProgressFromJson(Map<String, Object?> json) {
  final scoresJson = asJsonMap(json['scores']);
  final activeSeatsJson = asJsonList(json['activeSeats']);
  final nextStarter = PlayerSeat.fromName(asJsonString(json['nextStarter']));
  if (scoresJson == null || activeSeatsJson == null || nextStarter == null) {
    throw const FormatException('Invalid match report progress.');
  }
  return MatchProgressState(
    scores: _scoresFromJson(scoresJson),
    activeSeats: _seatListFromJson(activeSeatsJson),
    nextStarter: nextStarter,
    matchWinner: PlayerSeat.fromName(asJsonString(json['matchWinner'])),
  );
}

Map<String, Object?> _matchProgressToJson(MatchProgressState progress) {
  return {
    'scores': {
      for (final entry in progress.scores.entries) entry.key.name: entry.value,
    },
    'activeSeats': progress.activeSeats.map((seat) => seat.name).toList(),
    'nextStarter': progress.nextStarter.name,
    'matchWinner': progress.matchWinner?.name,
  };
}

Map<PlayerSeat, int> _scoresFromJson(Map<String, Object?> json) {
  return {
    for (final seat in PlayerSeat.values) seat: asJsonInt(json[seat.name]) ?? 0,
  };
}

List<PlayerSeat> _seatListFromJson(List<Object?> json) {
  final seats = <PlayerSeat>[];
  for (final raw in json) {
    final seat = PlayerSeat.fromName(raw is String ? raw : null);
    if (seat == null || seats.contains(seat)) {
      continue;
    }
    seats.add(seat);
  }
  if (seats.isEmpty) {
    throw const FormatException('Invalid match report seat list.');
  }
  return List.unmodifiable(seats);
}

RoundOutcomeType? _roundOutcomeTypeFromName(String? name) {
  if (name == null) {
    return null;
  }
  for (final type in RoundOutcomeType.values) {
    if (type.name == name) {
      return type;
    }
  }
  return null;
}
