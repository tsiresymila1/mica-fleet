import 'dart:convert';
import 'package:crypto/crypto.dart';

const genesisHash = 'GENESIS';

/// Hash d'un maillon du journal = SHA-256(seq | prevHash | dataHash).
/// Chaîner prevHash rend toute modification d'un maillon détectable.
String computeEntryHash(int seq, String prevHash, String dataHash) =>
    sha256.convert(utf8.encode('$seq|$prevHash|$dataHash')).toString();

/// Hash du contenu d'un événement.
String computeDataHash(String payload) =>
    sha256.convert(utf8.encode(payload)).toString();

class JournalLink {
  final int seq;
  final String prevHash;
  final String dataHash;
  final String entryHash;
  const JournalLink({
    required this.seq,
    required this.prevHash,
    required this.dataHash,
    required this.entryHash,
  });
}

/// Vérifie l'intégrité de la chaîne : chaînage prevHash + recalcul de chaque hash.
bool verifyChain(List<JournalLink> links) {
  final ordered = [...links]..sort((a, b) => a.seq.compareTo(b.seq));
  var prev = genesisHash;
  for (final l in ordered) {
    if (l.prevHash != prev) return false;
    if (l.entryHash != computeEntryHash(l.seq, l.prevHash, l.dataHash)) {
      return false;
    }
    prev = l.entryHash;
  }
  return true;
}
