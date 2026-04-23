import 'dart:convert';
import 'dart:io';

void main() {
  final dir = Directory('assets/translations');
  for (final file in dir.listSync().whereType<File>()) {
    if (file.path.endsWith('.json')) {
      print('Validating ${file.path}...');
      try {
        json.decode(file.readAsStringSync());
      } catch (e) {
        print('ERROR in ${file.path}: $e');
      }
    }
  }
}
