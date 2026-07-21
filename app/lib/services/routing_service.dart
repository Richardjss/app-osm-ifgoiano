import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  // Endereço local do GraphHopper.
  // Para emuladores Android, '10.0.2.2' mapeia para o localhost do computador host.
  // Para celular físico conectado, usar o IP local da máquina na rede (ex: 192.168.0.x).
  final String _baseUrl = 'http://192.168.0.30:8989/route';

  Future<Map<String, dynamic>> getBestRoute(List<LatLng> starts, List<LatLng> ends, String profile, {LatLng? parking}) async {
    Map<String, dynamic>? bestResult;
    double minTime = double.infinity; // GraphHopper otimiza por tempo
    
    // Executa as requisições em paralelo para não travar a UI
    List<Future<Map<String, dynamic>>> futures = [];
    
    for (var start in starts) {
      for (var end in ends) {
        futures.add(_getSingleRoute(start, end, profile, parking: parking));
      }
    }
    
    final results = await Future.wait(futures);
    
    for (var result in results) {
      if (result['points'].isNotEmpty) {
        double time = (result['time'] ?? double.infinity).toDouble();
        if (time < minTime) {
          minTime = time;
          bestResult = result;
        }
      }
    }
    
    return bestResult ?? {'points': <LatLng>[], 'distance': 0.0, 'time': 0};
  }

  Future<Map<String, dynamic>> _getSingleRoute(LatLng start, LatLng end, String profile, {LatLng? parking}) async {
    LatLng target = (parking != null && profile == 'carro') ? parking : end;
    final String url = '$_baseUrl?point=${start.latitude},${start.longitude}&point=${target.latitude},${target.longitude}&profile=$profile&points_encoded=false&locale=pt_BR&instructions=true&details=road_class';

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['paths'] != null && data['paths'].isNotEmpty) {
          final path = data['paths'][0];
          
          // Extraindo a geometria da rota
          final List coordinates = path['points']['coordinates'];
          List<LatLng> routePoints = coordinates.map((coord) {
            // No GeoJSON, é [longitude, latitude]
            return LatLng(coord[1], coord[0]);
          }).toList();
          
          List<dynamic> roadClassDetails = [];
          if (path['details'] != null && path['details']['road_class'] != null) {
            roadClassDetails = path['details']['road_class'];
          }
          
          Map<String, dynamic> result = {
            'points': routePoints,
            'distance': path['distance'], // em metros
            'time': path['time'], // em ms
            'instructions': path['instructions'], // passos textuais
            'road_class': roadClassDetails, // detalhes da via
            'used_start': start, // para a UI saber qual porta desenhar
            'used_end': end,
          };
          
          if (profile == 'carro' && routePoints.isNotEmpty) {
             final lastPoint = routePoints.last;
             const distCalc = Distance();
             final distToEnd = distCalc.as(LengthUnit.Meter, lastPoint, end);
             
             if (parking != null || distToEnd > 15.0) {
                final footUrl = '$_baseUrl?point=${lastPoint.latitude},${lastPoint.longitude}&point=${end.latitude},${end.longitude}&profile=pedestre&points_encoded=false&locale=pt_BR&instructions=true&details=road_class';
                try {
                  final footResp = await http.get(Uri.parse(footUrl)).timeout(const Duration(seconds: 5));
                  if (footResp.statusCode == 200) {
                     final footData = json.decode(footResp.body);
                     if (footData['paths'] != null && footData['paths'].isNotEmpty) {
                        final footPath = footData['paths'][0];
                        final List footCoords = footPath['points']['coordinates'];
                        List<LatLng> footPoints = footCoords.map((coord) => LatLng(coord[1], coord[0])).toList();
                        
                        int offset = routePoints.length - 1;
                        if (footPoints.isNotEmpty) footPoints.removeAt(0);
                        
                        if (result['instructions'].isNotEmpty) {
                           var lastInst = result['instructions'].last;
                           if (lastInst['sign'] == 4) {
                               result['instructions'].removeLast();
                           }
                        }
                        
                        List<dynamic> footInsts = List.from(footPath['instructions'] ?? []);
                        for (var inst in footInsts) {
                           if (inst['interval'] != null && inst['interval'].length >= 2) {
                              inst['interval'][0] += offset;
                              inst['interval'][1] += offset;
                           }
                        }
                        
                        footInsts.insert(0, {
                           'text': 'Estacione o veículo e siga a pé',
                           'distance': 0.0,
                           'time': 0,
                           'sign': 4,
                           'interval': [offset, offset]
                        });
                        
                        List<dynamic> footRoadClass = List.from(footPath['details']?['road_class'] ?? []);
                        for (var rc in footRoadClass) {
                           if (rc is List && rc.length >= 3) {
                              rc[0] += offset;
                              rc[1] += offset;
                           }
                        }
                        
                        result['pedestrian_start_index'] = offset;
                        result['points'].addAll(footPoints);
                        result['distance'] += footPath['distance'];
                        result['time'] += footPath['time'];
                        result['instructions'].addAll(footInsts);
                        result['road_class'].addAll(footRoadClass);
                     }
                  }
                } catch (e) {
                  print("Erro na rota complementar de pedestre: $e");
                }
             }
          }
          
          return result;
        }
      } else {
        print("Erro na API GraphHopper: ${response.statusCode}");
      }
    } catch (e) {
      print("Erro ao tentar conectar ao GraphHopper: $e");
    }
    
    return {'points': <LatLng>[], 'distance': 0.0, 'time': 0};
  }
}
