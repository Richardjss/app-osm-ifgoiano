import 'dart:io';
import 'dart:convert';

void main() async {
  final file = File('campus_clean.osm');
  if (!await file.exists()) {
    print('campus_clean.osm not found');
    return;
  }

  final content = await file.readAsString();
  final kerbs = [];
  
  final nodes = content.split('<node ');
  
  for (int i = 1; i < nodes.length; i++) {
    final nodeStr = nodes[i];
    final endIdx = nodeStr.indexOf('</node>');
    if (endIdx == -1) continue;
    
    final innerContent = nodeStr.substring(0, endIdx);
    
    bool hasKerbTag = innerContent.contains('k="barrier" v="kerb"') || 
                      innerContent.contains("k='barrier' v='kerb'") || 
                      innerContent.contains('k="kerb" v="raised"') || 
                      innerContent.contains("k='kerb' v='raised'") ||
                      innerContent.contains('k="kerb" v="lowered"') || 
                      innerContent.contains("k='kerb' v='lowered'");
                      
    bool isLowered = innerContent.contains('k="kerb" v="lowered"') || 
                     innerContent.contains("k='kerb' v='lowered'");
                     
    if (hasKerbTag) {
      // extract id, lat, lon
      final idMatch = RegExp(r'id=["\x27]([^"\x27]+)["\x27]').firstMatch(innerContent);
      final latMatch = RegExp(r'lat=["\x27]([^"\x27]+)["\x27]').firstMatch(innerContent);
      final lonMatch = RegExp(r'lon=["\x27]([^"\x27]+)["\x27]').firstMatch(innerContent);
      
      if (idMatch != null && latMatch != null && lonMatch != null) {
        kerbs.add({
          "id": idMatch.group(1),
          "lat": double.parse(latMatch.group(1)!),
          "lon": double.parse(lonMatch.group(1)!),
          "type": isLowered ? "lowered" : "raised"
        });
      }
    }
  }
  
  print('Found ${kerbs.length} kerbs.');
  
  final outputFile = File('../app/assets/kerbs.json');
  await outputFile.writeAsString(jsonEncode(kerbs));
  print('Written to kerbs.json');
}
