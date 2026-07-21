import 'dart:io';

void main() {
  var file = File('campus_clean.osm');
  var content = file.readAsStringSync();
  
  final wayBlocks = content.split('<way ');
  var newContent = wayBlocks[0];
  
  int count = 0;
  for (int i = 1; i < wayBlocks.length; i++) {
    final block = wayBlocks[i];
    final endIdx = block.indexOf('</way>');
    if (endIdx == -1) {
      newContent += '<way ' + block;
      continue;
    }
    
    var inner = block.substring(0, endIdx);
    if (inner.contains("k='motorcycle' v='yes'") || inner.contains('k="motorcycle" v="yes"')) {
      if (inner.contains("k='highway' v='footway'") || inner.contains("k='highway' v='path'")) {
        inner = inner.replaceAll("k='highway' v='footway'", "k='highway' v='service'");
        inner = inner.replaceAll('k="highway" v="footway"', 'k="highway" v="service"');
        inner = inner.replaceAll("k='highway' v='path'", "k='highway' v='service'");
        inner = inner.replaceAll('k="highway" v="path"', 'k="highway" v="service"');
        count++;
      }
    }
    
    newContent += '<way ' + inner + block.substring(endIdx);
  }
  
  file.writeAsStringSync(newContent);
  print('Fixed campus_clean.osm. Updated $count ways.');
}
