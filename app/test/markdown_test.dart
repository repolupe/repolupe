import 'package:app/util/markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('containsTable finds tables as they are rendered, also in lists and quotes', () {
    const table = '| a | b |\n| - | - |\n| 1 | 2 |';
    expect(containsTable('Text\n\n$table\n\nMore text'), isTrue);
    expect(containsTable('- item\n\n  $table'.replaceAll('\n|', '\n  |')), isTrue);
    expect(containsTable('> ${table.replaceAll('\n', '\n> ')}'), isTrue);

    expect(containsTable('No table here'), isFalse);
    expect(containsTable('```\n$table\n```'), isFalse);
    // Without a delimiter row, e.g. while the answer is still streaming.
    expect(containsTable('| a | b |\n| 1 | 2 |'), isFalse);
  });
}
