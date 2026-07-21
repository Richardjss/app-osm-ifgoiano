import 'dart:io';

void main() {
  var content = File('campus_clean.osm').readAsStringSync();
  final wayBlocks = content.split('<way ');
  for (int i = 1; i < wayBlocks.length; i++) {
    final block = wayBlocks[i];
    final endIdx = block.indexOf('</way>');
    if (endIdx == -1) continue;
    final inner = block.substring(0, endIdx);
    
    if (inner.contains('k="amenity" v="parking"') || inner.contains("k='amenity' v='parking'")) {
      print("--- PARKING WAY ---");
      // print first few lines of inner
      print(inner.split('\n').take(8).join('\n'));
    }
  }
}
