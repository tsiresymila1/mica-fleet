import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/journal/domain/journal_hash.dart';

JournalLink _link(int seq, String prev, String data) => JournalLink(
      seq: seq,
      prevHash: prev,
      dataHash: data,
      entryHash: computeEntryHash(seq, prev, data),
    );

void main() {
  test('computeEntryHash déterministe', () {
    expect(computeEntryHash(1, genesisHash, 'd'),
        computeEntryHash(1, genesisHash, 'd'));
  });

  test('chaîne valide vérifiée', () {
    final l1 = _link(1, genesisHash, 'a');
    final l2 = _link(2, l1.entryHash, 'b');
    expect(verifyChain([l1, l2]), isTrue);
  });

  test('détecte une donnée altérée', () {
    final l1 = _link(1, genesisHash, 'a');
    final l2 = _link(2, l1.entryHash, 'b');
    // Altère le dataHash de l2 sans recalculer entryHash
    final falsifie = JournalLink(
        seq: 2, prevHash: l1.entryHash, dataHash: 'HACK', entryHash: l2.entryHash);
    expect(verifyChain([l1, falsifie]), isFalse);
  });

  test('détecte un maillon retiré (chaînage rompu)', () {
    final l1 = _link(1, genesisHash, 'a');
    final l2 = _link(2, l1.entryHash, 'b');
    final l3 = _link(3, l2.entryHash, 'c');
    // On retire l2 → l3.prevHash ne correspond plus à l1
    expect(verifyChain([l1, l3]), isFalse);
  });
}
