import 'package:agent_wires_mcp/src/enrich/sourceloc_proposer.dart';
import 'package:test/test.dart';

void main() {
  test('returns proposal from enclosing function name', () {
    final proposal = SourceLocProposer.propose(
      creationLocation: 'test/fixtures/sample_widget_file.dart:5:12',
    );
    expect(proposal, isNotNull);
    expect(proposal!.source, 'source_location');
    expect(proposal.label.toLowerCase(), contains('remove'));
    expect(proposal.confidence, greaterThan(0));
    expect(proposal.confidence, lessThanOrEqualTo(1));
  });

  test('returns null when creation_location is malformed', () {
    expect(SourceLocProposer.propose(creationLocation: 'no-colons-here'), isNull);
    expect(SourceLocProposer.propose(creationLocation: null), isNull);
  });
}
