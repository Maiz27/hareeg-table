import '../../../domain/classic_hareeg/models/playing_card.dart';
import 'card_theme.dart';

/// Theme type that resolves bundled card artwork through a manifest.
abstract interface class AssetManifestCardTheme {
  /// Manifest that owns asset-backed card identity data.
  CardAssetManifest get assetManifest;
}

/// One standard-card face entry in an asset-backed theme.
class CardFaceAssetEntry {
  /// Creates a standard card face asset entry.
  const CardFaceAssetEntry({required this.identity, required this.path});

  /// Card identity represented by [path].
  final CardIdentity identity;

  /// Bundled asset path for [identity].
  final String path;

  /// Whether [path] carries the expected rank and suit identity slugs.
  bool get pathNamesIdentity {
    return path.contains(CardAssetManifest.rankSlug(identity.rank)) &&
        path.contains(identity.suit.name);
  }
}

/// Manifest for asset-backed card themes.
///
/// This module owns the mapping from game identities to bundled artwork paths.
/// Theme classes delegate asset lookup here, and tests verify manifest entries
/// instead of re-deriving asset identity from theme implementation details.
class CardAssetManifest {
  /// Creates a card asset manifest.
  const CardAssetManifest({
    required this.assetRoot,
    required Map<CardIdentity, String> standardFaces,
    required this.back,
    required this.redJoker,
    required this.blackJoker,
    Set<CardIdentity> bypassedFaces = const {},
  }) : _standardFaces = standardFaces,
       _bypassedFaces = bypassedFaces;

  /// Creates a complete standard 52-card manifest under [assetRoot].
  factory CardAssetManifest.standardDeck({
    required String assetRoot,
    required String? back,
    required String? redJoker,
    required String? blackJoker,
    String extension = 'webp',
    Set<CardIdentity> bypassedFaces = const {},
  }) {
    return CardAssetManifest(
      assetRoot: assetRoot,
      standardFaces: {
        for (final rank in CardRank.values)
          for (final suit in CardSuit.values)
            CardIdentity(rank: rank, suit: suit):
                '$assetRoot/${rankSlug(rank)}_${suit.name}.$extension',
      },
      back: back,
      redJoker: redJoker,
      blackJoker: blackJoker,
      bypassedFaces: bypassedFaces,
    );
  }

  /// Root directory for this bundled asset family.
  final String assetRoot;

  final Map<CardIdentity, String> _standardFaces;
  final Set<CardIdentity> _bypassedFaces;

  /// Bundled back artwork path.
  final String? back;

  /// Bundled red joker artwork path.
  final String? redJoker;

  /// Bundled black joker artwork path.
  final String? blackJoker;

  /// Standard face entries in the manifest.
  Iterable<CardFaceAssetEntry> get standardFaceEntries sync* {
    for (final entry in _standardFaces.entries) {
      yield CardFaceAssetEntry(identity: entry.key, path: entry.value);
    }
  }

  /// Returns the standard face asset path for [identity], if available.
  String? standardFace(CardIdentity identity) {
    if (_bypassedFaces.contains(identity)) {
      return null;
    }
    return _standardFaces[identity];
  }

  /// Returns the joker asset path for the physical joker copy.
  String? jokerFace({required int jokerIndex}) {
    return jokerIndex.isEven ? redJoker : blackJoker;
  }

  /// Resolves the asset path for a card render request.
  String? assetFor(CardRenderRequest request) {
    if (request.faceDown || request.variant == CardVariant.back) {
      return back;
    }

    final card = request.card;
    if (card.isJoker) {
      return jokerFace(jokerIndex: card.jokerIndex ?? 0);
    }

    final identity = card.identity ?? card.representedIdentity;
    if (identity == null) {
      return null;
    }
    return standardFace(identity);
  }

  /// Slug used by standard deck asset filenames.
  static String rankSlug(CardRank rank) {
    return switch (rank) {
      CardRank.ace => 'ace',
      CardRank.two => 'two',
      CardRank.three => 'three',
      CardRank.four => 'four',
      CardRank.five => 'five',
      CardRank.six => 'six',
      CardRank.seven => 'seven',
      CardRank.eight => 'eight',
      CardRank.nine => 'nine',
      CardRank.ten => 'ten',
      CardRank.jack => 'jack',
      CardRank.queen => 'queen',
      CardRank.king => 'king',
    };
  }
}
