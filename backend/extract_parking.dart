import 'dart:io';
import 'dart:convert';

void main() async {
  final file = File('campus_clean.osm');
  if (!await file.exists()) {
    print('campus_clean.osm not found');
    return;
  }

  final content = await file.readAsString();
  
  // 1. Extrair todos os nós para um mapa: id -> [lat, lon]
  Map<String, List<double>> nodeMap = {};
  final nodeRegex = RegExp(r'<node\s+id=["\x27]([^"\x27]+)["\x27][^>]+lat=["\x27]([^"\x27]+)["\x27]\s+lon=["\x27]([^"\x27]+)["\x27]');
  for (final match in nodeRegex.allMatches(content)) {
    final id = match.group(1)!;
    final lat = double.parse(match.group(2)!);
    final lon = double.parse(match.group(3)!);
    nodeMap[id] = [lat, lon];
  }
  
  print('Parsed ${nodeMap.length} nodes.');

  final parkings = [];

  // 2. Procurar nós que sejam estacionamentos diretamente
  final nodeBlocks = content.split('<node ');
  for (int i = 1; i < nodeBlocks.length; i++) {
    final block = nodeBlocks[i];
    final endIdx = block.indexOf('</node>');
    if (endIdx == -1) continue;
    final inner = block.substring(0, endIdx);
    
    if (inner.contains('k="amenity" v="parking"') || inner.contains("k='amenity' v='parking'")) {
      final idMatch = RegExp(r'id=["\x27]([^"\x27]+)["\x27]').firstMatch(inner);
      
      bool? allowsCar;
      bool? allowsMoto;
      final carMatch = RegExp(r'k=["\x27]car["\x27]\s+v=["\x27]([^"\x27]+)["\x27]').firstMatch(inner);
      if (carMatch != null) allowsCar = carMatch.group(1) == 'yes';
      
      final motoMatch = RegExp(r'k=["\x27]motorcycle["\x27]\s+v=["\x27]([^"\x27]+)["\x27]').firstMatch(inner);
      if (motoMatch != null) allowsMoto = motoMatch.group(1) == 'yes';
      
      if (idMatch != null) {
        final id = idMatch.group(1)!;
        if (nodeMap.containsKey(id)) {
          parkings.add({
            "id": id,
            "lat": nodeMap[id]![0],
            "lon": nodeMap[id]![1],
            "car": allowsCar,
            "motorcycle": allowsMoto
          });
        }
      }
    }
  }

  // 3. Procurar vias (polígonos) que sejam estacionamentos
  final wayBlocks = content.split('<way ');
  for (int i = 1; i < wayBlocks.length; i++) {
    final block = wayBlocks[i];
    final endIdx = block.indexOf('</way>');
    if (endIdx == -1) continue;
    final inner = block.substring(0, endIdx);
    
    if (inner.contains('k="amenity" v="parking"') || inner.contains("k='amenity' v='parking'")) {
      final idMatch = RegExp(r'id=["\x27]([^"\x27]+)["\x27]').firstMatch(inner);
      final id = idMatch?.group(1) ?? "way_$i";
      
      bool? allowsCar;
      bool? allowsMoto;
      final carMatch = RegExp(r'k=["\x27]car["\x27]\s+v=["\x27]([^"\x27]+)["\x27]').firstMatch(inner);
      if (carMatch != null) allowsCar = carMatch.group(1) == 'yes';
      
      final motoMatch = RegExp(r'k=["\x27]motorcycle["\x27]\s+v=["\x27]([^"\x27]+)["\x27]').firstMatch(inner);
      if (motoMatch != null) allowsMoto = motoMatch.group(1) == 'yes';
      
      // Extrair todos os nós (nd ref)
      final ndRegex = RegExp(r'<nd\s+ref=["\x27]([^"\x27]+)["\x27]\s*/>');
      final ndMatches = ndRegex.allMatches(inner);
      
      double sumLat = 0.0;
      double sumLon = 0.0;
      int count = 0;
      
      for (final match in ndMatches) {
        final refId = match.group(1)!;
        if (nodeMap.containsKey(refId)) {
          sumLat += nodeMap[refId]![0];
          sumLon += nodeMap[refId]![1];
          count++;
        }
      }
      
      if (count > 0) {
        parkings.add({
          "id": id,
          "lat": sumLat / count,
          "lon": sumLon / count,
          "car": allowsCar,
          "motorcycle": allowsMoto
        });
      }
    }
  }
  
  print('Found ${parkings.length} parking lots.');
  
  final outputFile = File('../app/assets/parking.json');
  await outputFile.writeAsString(jsonEncode(parkings));
  print('Written to parking.json');
}
