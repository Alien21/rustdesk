import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'last used follows recent sessions before peers without local history',
    () {
      final peers = [
        Peer.fromJson({'id': 'older', 'alias': 'A'}),
        Peer.fromJson({'id': 'unused-b', 'alias': 'Unused B'}),
        Peer.fromJson({'id': 'newest', 'alias': 'Z'}),
        Peer.fromJson({'id': 'unused-a', 'alias': 'Unused A'}),
      ];
      sortPeersByLastUsed(peers, ['newest', 'outside-address-book', ' older']);
      expect(peers.map((peer) => peer.id), [
        'newest',
        'older',
        'unused-a',
        'unused-b',
      ]);
    },
  );

  test(
    'last used follows an updated recent order without changing peer data',
    () {
      final first = Peer.fromJson({'id': 'first', 'alias': 'First PC'});
      final second = Peer.fromJson({
        'id': 'second',
        'tags': ['Work'],
      });
      final peers = [first, second];
      sortPeersByLastUsed(peers, ['second', 'first']);
      expect(peers, [second, first]);
      sortPeersByLastUsed(peers, ['first', 'second']);
      expect(peers, [first, second]);
      expect(first.alias, 'First PC');
      expect(second.tags, ['Work']);
    },
  );
}
