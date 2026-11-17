import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/dashboard/dashboard_block.dart';

void main() {
  test('brake_level se lit, mode compact compris', () {
    final block = DashboardBlock.parse({'kind': 'brake_level', 'mode': 'compact'});
    expect(block, isA<BrakeLevelBlock>());
    expect((block! as BrakeLevelBlock).mode, BrakeLevelMode.compact);
  });

  test('brake_level sans mode retombe sur le mode large', () {
    final block = DashboardBlock.parse({'kind': 'brake_level'});
    expect((block! as BrakeLevelBlock).mode, BrakeLevelMode.full);
  });
}
