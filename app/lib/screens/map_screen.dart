import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/routing_service.dart';

enum MapState { defaultView, placeSelected, routePlanning, navigating, manualSelection }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();
  
  final LatLng _campusCenter = const LatLng(-17.8038, -50.9056);
  final LatLng _defaultStartPoint = const LatLng(-17.803512, -50.907289);
  
  List<dynamic> _pois = [];
  List<dynamic> _crosswalks = [];
  List<dynamic> _parkings = [];
  List<dynamic> _kerbs = [];
  List<dynamic> _routeKerbs = [];
  List<LatLng> _currentRoute = [];
  List<Polyline> _routePolylines = [];
  List<Marker> _warningMarkers = [];
  
  final FlutterTts _flutterTts = FlutterTts();
  List<dynamic> _instructions = [];
  int _currentInstructionIndex = 0;
  StreamSubscription<Position>? _positionStream;
  
  // Variáveis para modo de simulação
  bool _isSimulating = false;
  double _simulationSpeed = 1.0;
  bool _isVoiceMuted = false;
  Timer? _simulationTimer;
  int _simulationRouteIndex = 0;
  
  // Variáveis para navegação 3ª pessoa e simulação aprimorada
  bool _isAutoCentering = true;
  double _currentBearing = 0.0;
  bool _isSimulationPaused = false;
  double _simulationDistanceCovered = 0.0;
  double _distanceToNextStep = 0.0;
  double? _lastDistanceToNextStep;
  Set<int> _spokenInstructions = {};
  
  MapState _mapState = MapState.defaultView;
  
  String _selectedProfile = 'carro';
  
  Map<String, Map<String, dynamic>> _routeResults = {};
  bool _isCalculatingRoutes = false;
  bool _isSelectingOrigin = false;
  
  Map<String, dynamic>? _selectedPoi;
  Map<String, dynamic>? _selectedRoom;
  String? _destinationBuildingName;
  double _currentZoom = 16.0;

  final List<Map<String, dynamic>> _profileData = [
    {'id': 'carro', 'icon': Icons.directions_car, 'label': 'Automóveis'},
    {'id': 'pedestre', 'icon': Icons.directions_walk, 'label': 'Pedestre'},
    {'id': 'cadeirante', 'icon': Icons.accessible, 'label': 'Cadeirante'},
    {'id': 'deficiente_visual', 'icon': Icons.blind, 'label': 'Def. Visual'},
  ];
  
  LatLng? _startPoint;
  LatLng? _endPoint;
  List<dynamic>? _startEntrances;
  List<dynamic>? _endEntrances;
  LatLng? _currentLocation;
  LatLng? _realLocation;
  String _destinationName = '';
  String _startPointName = 'Meu Local';

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadPOIs();
    _checkLocationPermission();
  }
  
  @override
  void dispose() {
    _stopNavigation();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("pt-BR");
    await _flutterTts.setSpeechRate(0.5);
  }
  
  void _showFeedbackDialog() {
    TextEditingController feedbackController = TextEditingController();
    bool includeLocation = true;
    String selectedType = "Melhoria Geral";
    final List<String> feedbackTypes = [
      "Melhoria Geral",
      "Nome Incorreto",
      "Falta Rampa de Acesso",
      "Via Interditada/Esburacada",
      "Sala não existe/fechada",
      "Rota Calculada Errada"
    ];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Theme(
          data: ThemeData.light(),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  left: 20, right: 20, top: 20
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Reportar Erro ou Sugerir Melhoria", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 15),
                    const Text("Tipo do problema:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                    DropdownButton<String>(
                      value: selectedType,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      style: const TextStyle(color: Colors.black87, fontSize: 16),
                      items: feedbackTypes.map((String type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setModalState(() {
                          selectedType = newValue!;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text("Descreva mais detalhes:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: feedbackController,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.black87),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: "Sua descrição detalhada...",
                        hintStyle: TextStyle(color: Colors.black54),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: includeLocation,
                        onChanged: (val) {
                          setModalState(() { includeLocation = val ?? true; });
                        },
                      ),
                      const Expanded(child: Text("Anexar minha localização e ponto selecionado no mapa", style: TextStyle(color: Colors.black87))),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        String desc = feedbackController.text;
                        if (desc.trim().isEmpty) return;
                        
                        String locationInfo = "Localização: Desconhecida";
                        if (includeLocation) {
                          locationInfo = _currentLocation != null ? "Localização GPS: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}" : "Sem sinal GPS";
                          if (_destinationName != null && _destinationName!.isNotEmpty) {
                            locationInfo += "\nAlvo Selecionado: $_destinationName";
                          }
                        }

                        // URL do Webhook do seu servidor Discord
                        const String webhookUrl = "https://discord.com/api/webhooks/1528616764626174013/twPRUydEEtWjgNg1kHZJH4QPDparS5-6XR7-sFLu5ARupy9t-WxjEjeG5LnWnh88Y9iN"; 
                        
                        try {
                          await http.post(
                            Uri.parse(webhookUrl),
                            headers: {"Content-Type": "application/json"},
                            body: jsonEncode({
                              "content": "🚨 **Novo Reporte no Mapa OSM** 🚨\n"
                                         "**Tipo:** $selectedType\n"
                                         "**Descrição:** $desc\n"
                                         "**$locationInfo**"
                            }),
                          );
                        } catch (e) {
                          print("Erro ao enviar Webhook: $e");
                        }
                        
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Obrigado pelo feedback! Isso nos ajuda a melhorar o mapa.")),
                        );
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                      child: const Text("Enviar Relatório"),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          }
        ),
        );
      }
    );
  }

  Future<void> _loadPOIs() async {
    try {
      final String response = await rootBundle.loadString('assets/pois.json');
      final data = await json.decode(response) as List<dynamic>;
      
      const distance = Distance();
      final filteredPois = data.where((poi) {
        final poiLatLng = LatLng(poi['lat'], poi['lon']);
        final dist = distance.as(LengthUnit.Meter, _campusCenter, poiLatLng);
        return dist <= 1300.0;
      }).toList();

      List<dynamic> loadedCrosswalks = [];
      try {
        final String crosswalksResponse = await rootBundle.loadString('assets/crosswalks.json');
        loadedCrosswalks = await json.decode(crosswalksResponse) as List<dynamic>;
      } catch (e) {
        debugPrint("Sem arquivo de faixas: $e");
      }

      List<dynamic> loadedKerbs = [];
      try {
        final String kerbsResponse = await rootBundle.loadString('assets/kerbs.json');
        loadedKerbs = await json.decode(kerbsResponse) as List<dynamic>;
      } catch (e) {
        debugPrint("Sem arquivo de meios-fios: $e");
      }

      List<dynamic> loadedParkings = [];
      try {
        final String parkingResponse = await rootBundle.loadString('assets/parking.json');
        loadedParkings = await json.decode(parkingResponse) as List<dynamic>;
      } catch (e) {
        debugPrint("Sem arquivo de estacionamentos: $e");
      }

      setState(() {
        _pois = filteredPois;
        _crosswalks = loadedCrosswalks;
        _kerbs = loadedKerbs;
        _parkings = loadedParkings;
      });
    } catch (e) {
      debugPrint("Erro ao carregar locais: $e");
    }
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;
    
    Position pos = await Geolocator.getCurrentPosition();
    setState(() {
      _realLocation = LatLng(pos.latitude, pos.longitude);
      if (!_isSimulating) {
        _currentLocation = _realLocation;
      }
    });
    _mapController.move(_realLocation!, 17.0);
    
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _realLocation = LatLng(position.latitude, position.longitude);
          if (!_isSimulating) {
            _currentLocation = _realLocation;
          }
        });
      }
    });
  }


  bool _isPointInPolygon(LatLng point, List<dynamic> polygonCoords) {
    bool c = false;
    int j = polygonCoords.length - 1;
    for (int i = 0; i < polygonCoords.length; i++) {
      double latI = (polygonCoords[i][0] as num).toDouble();
      double lonI = (polygonCoords[i][1] as num).toDouble();
      double latJ = (polygonCoords[j][0] as num).toDouble();
      double lonJ = (polygonCoords[j][1] as num).toDouble();
      
      if (((lonI > point.longitude) != (lonJ > point.longitude)) &&
          (point.latitude < (latJ - latI) * (point.longitude - lonI) / (lonJ - lonI) + latI)) {
        c = !c;
      }
      j = i;
    }
    return c;
  }

  dynamic _getNearestPoi(LatLng point) {
    // Verifica se o toque caiu exatamente DENTRO do polígono de um prédio
    for (var poi in _pois) {
      if (poi['polygon'] != null) {
        if (_isPointInPolygon(point, poi['polygon'])) {
          return poi;
        }
      }
    }

    dynamic nearestPoi;
    final Distance distance = const Distance();
    double minDistance = 15.0;
    
    for (var poi in _pois) {
      final poiPoint = LatLng(poi['lat'], poi['lon']);
      final dist = distance.as(LengthUnit.Meter, point, poiPoint);
      if (dist < minDistance) {
        minDistance = dist;
        nearestPoi = poi;
      }
    }
    return nearestPoi;
  }

  List<dynamic> _getEntrancesForPoi(dynamic poi) {
    if (poi['entrances'] != null && (poi['entrances'] as List).isNotEmpty) {
      return poi['entrances'] as List;
    }
    return [{'lat': poi['lat'], 'lon': poi['lon']}];
  }

  double _distanceToSegment(LatLng p, LatLng v, LatLng w) {
    double latMid = (v.latitude + w.latitude) / 2.0;
    double metersPerLat = 111320.0;
    double metersPerLon = 111320.0 * cos(latMid * pi / 180.0);
    
    double px = p.longitude * metersPerLon;
    double py = p.latitude * metersPerLat;
    double vx = v.longitude * metersPerLon;
    double vy = v.latitude * metersPerLat;
    double wx = w.longitude * metersPerLon;
    double wy = w.latitude * metersPerLat;
    
    double l2 = pow(vx - wx, 2).toDouble() + pow(vy - wy, 2).toDouble();
    if (l2 == 0.0) return const Distance().as(LengthUnit.Meter, p, v).toDouble();
    
    double t = max(0.0, min(1.0, ((px - vx) * (wx - vx) + (py - vy) * (wy - vy)) / l2));
    double projX = vx + t * (wx - vx);
    double projY = vy + t * (wy - vy);
    
    return sqrt(pow(px - projX, 2).toDouble() + pow(py - projY, 2).toDouble());
  }

  void _onMapLongPress(TapPosition tapPosition, LatLng point) {
    if (_mapState == MapState.navigating) return;
    
    setState(() {
      _endPoint = point;
      if (_startPoint == null) {
        if (_currentLocation != null) {
          _startPoint = _currentLocation;
          _startPointName = "Meu Local";
        } else {
          _startPoint = _defaultStartPoint;
          _startPointName = "Entrada do IF";
        }
      }
      
      final poi = _getNearestPoi(point);
      if (poi != null) {
        _endPoint = LatLng(poi['lat'], poi['lon']);
        _endEntrances = _getEntrancesForPoi(poi);
        _destinationName = poi['name'];
        _selectedPoi = poi;
        _destinationBuildingName = null;
      } else {
        _endPoint = point;
        _destinationName = "${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}";
        _selectedPoi = null;
        _destinationBuildingName = null;
      }
      _selectedRoom = null;
      _mapState = MapState.placeSelected;
      _currentRoute = [];
      _routePolylines = [];
      _warningMarkers = [];
      _lastDistanceToNextStep = null;
      _spokenInstructions.clear();
    });
    
    _mapController.move(point, _mapController.camera.zoom);
  }
  
  void _onMapTap(TapPosition tapPosition, LatLng point) {
    // Agora o painel sÃ³ fecha no botÃ£o X
  }

  Future<void> _selectPoint({required bool isOrigin}) async {
    final selectedPoi = await showSearch(
      context: context,
      delegate: PoiSearchDelegate(pois: _pois, currentLocation: _currentLocation),
    );
    
    if (selectedPoi != null) {
      if (selectedPoi['type'] == 'manual_selection') {
        setState(() {
          _mapState = MapState.manualSelection;
          _isSelectingOrigin = isOrigin;
        });
        return;
      }

      setState(() {
        final name = selectedPoi['name'];
        if (selectedPoi['is_room'] == true) {
          if (isOrigin) {
            _startPoint = LatLng(selectedPoi['lat'], selectedPoi['lon']);
            _startPointName = name;
          } else {
            _endPoint = LatLng(selectedPoi['lat'], selectedPoi['lon']);
            _destinationName = name;
            _destinationBuildingName = selectedPoi['parent_name'];
          }
        } else {
          if (isOrigin) {
            _startPoint = LatLng(selectedPoi['lat'], selectedPoi['lon']);
            _startEntrances = _getEntrancesForPoi(selectedPoi);
            _startPointName = name;
          } else {
            _endPoint = LatLng(selectedPoi['lat'], selectedPoi['lon']);
            _endEntrances = _getEntrancesForPoi(selectedPoi);
            _destinationName = name;
            _destinationBuildingName = null;
          }
        }
        
        if (_startPoint != null && _endPoint != null) {
          _calculateAllRoutes();
        }
      });
      _mapController.move(isOrigin ? _startPoint! : _endPoint!, 17.0);
    }
  }

  void _swapPoints() {
    setState(() {
      final tempPoint = _startPoint;
      _startPoint = _endPoint;
      _endPoint = tempPoint;
      
      final tempEntrances = _startEntrances;
      _startEntrances = _endEntrances;
      _endEntrances = tempEntrances;
      
      final tempName = _startPointName;
      _startPointName = _destinationName;
      _destinationName = tempName;
      
      if (_startPoint != null && _endPoint != null) {
        _calculateAllRoutes();
      } else {
        _startEntrances = null;
        _endEntrances = null;
        _currentRoute = [];
        _routePolylines = [];
        _warningMarkers = [];
        _routeResults.clear();
        _lastDistanceToNextStep = null;
        _spokenInstructions.clear();
      }
    });
  }

  Future<void> _calculateAllRoutes() async {
    if (_startPoint == null || _endPoint == null) return;
    
    setState(() {
      _mapState = MapState.routePlanning;
      _isCalculatingRoutes = true;
      _routeResults.clear();
    });
    
    await Future.wait(_profileData.map((profile) async {
      final pid = profile['id'] as String;
      
      LatLng? bestParking;
      if (pid == 'carro') {
        double minD = double.infinity;
        for (var p in _parkings) {
          if (pid == 'carro' && p['car'] == false) continue;
          
          LatLng pLatLng = LatLng(p['lat'], p['lon']);
          double d = const Distance().as(LengthUnit.Meter, _endPoint!, pLatLng);
          if (d < minD && d < 800) {
            minD = d;
            bestParking = pLatLng;
          }
        }
      }
      
      List<LatLng> starts = [];
      if (_startEntrances != null) {
        bool hasWheelchairYes = _startEntrances!.any((e) => e['wheelchair'] == 'yes');
        for (var e in _startEntrances!) {
          if (pid == 'cadeirante') {
            if (e['wheelchair'] == 'no') continue;
            if (hasWheelchairYes && e['wheelchair'] != 'yes') continue;
          }
          starts.add(LatLng(e['lat'], e['lon']));
        }
      }
      if (starts.isEmpty) starts = [_startPoint!];

      List<LatLng> ends = [];
      if (_endEntrances != null) {
        bool hasWheelchairYes = _endEntrances!.any((e) => e['wheelchair'] == 'yes');
        for (var e in _endEntrances!) {
          if (pid == 'cadeirante') {
            if (e['wheelchair'] == 'no') continue;
            if (hasWheelchairYes && e['wheelchair'] != 'yes') continue;
          }
          ends.add(LatLng(e['lat'], e['lon']));
        }
      }
      if (ends.isEmpty) ends = [_endPoint!];
      
      final result = await _routingService.getBestRoute(starts, ends, pid, parking: bestParking);
      if (result['points'].isNotEmpty) {
        _routeResults[pid] = result;
      }
    }));
    
    if (mounted) {
      setState(() {
        _isCalculatingRoutes = false;
        _applySelectedRoute();
      });
    }
  }
  
  void _applySelectedRoute() {
    if (_routeResults.containsKey(_selectedProfile)) {
      final res = _routeResults[_selectedProfile]!;
      _currentRoute = res['points'];
      
      List<dynamic> rawInsts = List.from(res['instructions'] ?? []);
      List<dynamic> processedInsts = [];
      const distance = Distance();
      Set<String> alertedCrosswalks = {};
      Set<String> alertedKerbs = {};
      LatLng? lastCrosswalkAlertPoint;
      LatLng? lastKerbAlertPoint;
      
      if (res['used_start'] != null) _startPoint = res['used_start'];
      if (res['used_end'] != null) _endPoint = res['used_end'];
      
      _routePolylines = [];
      _warningMarkers = [];
      _routeKerbs = [];
      List<dynamic> roadClassDetails = res['road_class'] ?? [];
      
      int pedStart = res['pedestrian_start_index'] ?? -1;
      
      if (_selectedProfile == 'pedestre' && roadClassDetails.isNotEmpty) {
        for (var segment in roadClassDetails) {
          if (segment is List && segment.length >= 3) {
            int startIdx = segment[0];
            int endIdx = segment[1];
            String roadClass = segment[2].toString().toLowerCase();
            
            bool isSharedRoad = ['residential', 'tertiary', 'secondary', 'primary', 'unclassified'].contains(roadClass);
            
            if (startIdx >= 0 && endIdx < _currentRoute.length && startIdx <= endIdx) {
              List<LatLng> segmentPoints = _currentRoute.sublist(startIdx, endIdx + 1);
              
              _routePolylines.add(
                Polyline(
                  points: segmentPoints,
                  strokeWidth: 6.0,
                  color: isSharedRoad ? Colors.amber : Colors.blueAccent.shade700,
                )
              );
            }
          }
        }
      } else if (_currentRoute.isNotEmpty) {
         if (pedStart != -1 && pedStart > 0 && pedStart < _currentRoute.length) {
            _routePolylines.add(
              Polyline(
                points: _currentRoute.sublist(0, pedStart + 1),
                strokeWidth: 6.0,
                color: Colors.blueAccent.shade700,
              )
            );
            _routePolylines.add(
              Polyline(
                points: _currentRoute.sublist(pedStart),
                strokeWidth: 6.0,
                color: Colors.orange,
                pattern: StrokePattern.dashed(segments: [15.0, 15.0]),
              )
            );
         } else {
            _routePolylines.add(
              Polyline(
                points: _currentRoute,
                strokeWidth: 6.0,
                color: Colors.blueAccent.shade700,
              )
            );
         }
      }
      
      bool alreadyInsideBuilding = false;
      if (_currentRoute.isNotEmpty && _destinationBuildingName != null && _selectedPoi != null && _selectedPoi!['polygon'] != null) {
        alreadyInsideBuilding = _isPointInPolygon(_currentRoute.first, _selectedPoi!['polygon']);
      }
      
      bool buildingEntranceAdded = false;
      
      int parkingPointIndex = _currentRoute.length;
      if (_selectedProfile == 'carro') {
         for (var inst in rawInsts) {
            if (inst['text'].toString().contains('Estacione')) {
                if (inst['interval'] != null && inst['interval'].isNotEmpty) {
                    parkingPointIndex = inst['interval'][0];
                }
                break;
            }
         }
      }
      
      for (int i = 0; i < rawInsts.length; i++) {
        var inst = rawInsts[i];
        
        bool isSharedRoadInstruction = false;
        if (_selectedProfile == 'pedestre' && inst['interval'] != null && inst['interval'].length >= 2) {
          int startIdx = inst['interval'][0];
          int endIdx = inst['interval'][1];
          for (var segment in roadClassDetails) {
            if (segment is List && segment.length >= 3) {
              int segStart = segment[0];
              int segEnd = segment[1];
              String roadClass = segment[2].toString().toLowerCase();
              bool isSharedRoad = ['residential', 'tertiary', 'secondary', 'primary', 'unclassified'].contains(roadClass);
              
              if (isSharedRoad) {
                // Checar sobreposição de intervalos
                if (startIdx <= segEnd && endIdx >= segStart) {
                  isSharedRoadInstruction = true;
                  break;
                }
              }
            }
          }
        }
        
        Map<String, dynamic> modifiedInst = Map<String, dynamic>.from(inst as Map);
        
        // Simplificar o texto (remover nome da rua para a voz não ficar muito longa)
        if (modifiedInst['text'] != null) {
            String txt = modifiedInst['text'].toString();
            // Corta a partir do " na ", " no ", " em " para limpar o nome da via
            int idxNa = txt.indexOf(" na ");
            int idxNo = txt.indexOf(" no ");
            int idxEm = txt.indexOf(" em ");
            
            int minIdx = txt.length;
            if (idxNa != -1 && idxNa < minIdx) minIdx = idxNa;
            if (idxNo != -1 && idxNo < minIdx) minIdx = idxNo;
            if (idxEm != -1 && idxEm < minIdx) minIdx = idxEm;
            
            if (minIdx < txt.length) {
                txt = txt.substring(0, minIdx).trim();
            }
            
            if (txt.toLowerCase() == 'continue' || txt.toLowerCase() == 'continuar') {
                double dist = (modifiedInst['distance'] ?? 0.0).toDouble();
                if (dist > 20) {
                    txt = 'Continue em frente por ${dist.round()} metros';
                } else {
                    txt = 'Continue em frente';
                }
            }
            
            if (modifiedInst['sign'] == 4) {
                txt = 'Chegou em $_destinationName';
            }
            
            modifiedInst['text'] = txt;
        }
        
        if (isSharedRoadInstruction) {
          modifiedInst['isSharedRoad'] = true;
        }
        modifiedInst['isCustom'] = false;
        
        bool isCarSegment = (_selectedProfile == 'carro' && (inst['interval'] != null && inst['interval'].isNotEmpty ? inst['interval'][0] <= parkingPointIndex : true));
        if (isCarSegment) {
            modifiedInst['trigger_distance'] = 20.0;
        }
        
        processedInsts.add(modifiedInst);

      } // Fim do loop das instruções padrão do GraphHopper

      // Nova varredura para faixas, meios-fios e prédios
      double accumulatedDistance = 0.0;
      
      // Calcular distância exata para cada instrução padrão (baseado no interval[0])
      for (var pInst in processedInsts) {
         if (pInst['interval'] != null && pInst['interval'].isNotEmpty) {
             int idx = pInst['interval'][0];
             double dist = 0.0;
             for (int i = 0; i < idx && i < _currentRoute.length - 1; i++) {
                dist += distance.as(LengthUnit.Meter, _currentRoute[i], _currentRoute[i + 1]);
             }
             pInst['exactDistance'] = dist;
         } else {
             pInst['exactDistance'] = 0.0;
         }
      }
      
      for (int p = 0; p < _currentRoute.length - 1; p++) {
         LatLng v = _currentRoute[p];
         LatLng w = _currentRoute[p + 1];
         double segmentLength = distance.as(LengthUnit.Meter, v, w);
         
         bool isCarSegment = (_selectedProfile == 'carro' && p < parkingPointIndex);
         double triggerDist = isCarSegment ? 20.0 : 10.0;
         
         if (!alreadyInsideBuilding && !buildingEntranceAdded && _destinationBuildingName != null && _selectedPoi != null && _selectedPoi!['polygon'] != null) {
             if (_isPointInPolygon(v, _selectedPoi!['polygon'])) {
                 buildingEntranceAdded = true;
                 processedInsts.add({
                     'text': 'Entrando no prédio: $_destinationBuildingName',
                     'distance': 0.0,
                     'time': 0,
                     'sign': 4,
                     'interval': [p, p],
                     'isCustom': true,
                     'targetLatLng': v,
                     'exactDistance': accumulatedDistance,
                     'trigger_distance': 15.0,
                 });
             }
         }
         
         // Checar faixas
         for (var cw in _crosswalks) {
            String cwId = cw['id'].toString();
            if (alertedCrosswalks.contains(cwId)) continue;
            LatLng cwPoint = LatLng(cw['lat'], cw['lon']);
            if (_distanceToSegment(cwPoint, v, w) < 1.0) {
               alertedCrosswalks.add(cwId);
               double distV = distance.as(LengthUnit.Meter, cwPoint, v);
               int exactIndex = (distV > segmentLength / 2) ? p + 1 : p;
                   processedInsts.add({
                     'text': 'Faixa de pedestres à frente',
                     'distance': 0.0,
                     'time': 0,
                     'sign': 0,
                     'interval': [exactIndex, exactIndex],
                     'trigger_distance': triggerDist,
                     'isCustom': true,
                     'targetLatLng': cwPoint,
                     'exactDistance': accumulatedDistance + distV,
                   });
                }
             }
             
             // Checar meios-fios/rampas
             if (_selectedProfile == 'cadeirante' || _selectedProfile == 'deficiente_visual') {
                for (var kerb in _kerbs) {
                   String kerbId = kerb['id'].toString();
                   if (alertedKerbs.contains(kerbId)) continue;
                   LatLng kerbPoint = LatLng(kerb['lat'], kerb['lon']);
                   if (_distanceToSegment(kerbPoint, v, w) < 1.0) {
                      alertedKerbs.add(kerbId);
                      _routeKerbs.add(kerb);
                      double distV = distance.as(LengthUnit.Meter, kerbPoint, v);
                      int exactIndex = (distV > segmentLength / 2) ? p + 1 : p;
                      processedInsts.add({
                        'text': kerb['type'] == 'raised' ? 'Atenção: Meio-fio à frente' : 'Passagem com rampa',
                        'distance': 0.0,
                        'time': 0,
                        'sign': 0,
                        'interval': [exactIndex, exactIndex],
                        'trigger_distance': 5.0,
                        'isCustom': true,
                        'targetLatLng': kerbPoint,
                        'exactDistance': accumulatedDistance + distV,
                      });
                   }
                }
             }
         
         accumulatedDistance += segmentLength;
      }
      
      // Fallback prédio
      if (!buildingEntranceAdded && !alreadyInsideBuilding && _destinationBuildingName != null && _destinationName != _destinationBuildingName && processedInsts.isNotEmpty) {
          int lastIndex = _currentRoute.isNotEmpty ? _currentRoute.length - 1 : 0;
          processedInsts.add({
              'text': 'Entrando no prédio: $_destinationBuildingName',
              'distance': 0.0,
              'time': 0,
              'sign': 4,
              'interval': [lastIndex, lastIndex],
              'isCustom': true,
              'exactDistance': accumulatedDistance - 0.1,
          });
      }
      
      // ORDENAÇÃO
      processedInsts.sort((a, b) {
         double distA = (a['exactDistance'] ?? 0.0).toDouble();
         double distB = (b['exactDistance'] ?? 0.0).toDouble();
         if (distA != distB) {
            return distA.compareTo(distB);
         }
         bool isCustomA = a['isCustom'] == true;
         bool isCustomB = b['isCustom'] == true;
         if (!isCustomA && isCustomB) return -1;
         if (isCustomA && !isCustomB) return 1;
         return 0;
      });
      
      // AGRUPAMENTO
      List<Map<String, dynamic>> finalInsts = [];
      for (var inst in processedInsts) {
         if (finalInsts.isNotEmpty && inst['isCustom'] == true) {
            var lastInst = finalInsts.last;
            if (lastInst['isCustom'] == true && lastInst['text'] == inst['text']) {
               double distA = (inst['exactDistance'] ?? 0.0).toDouble();
               double distB = (lastInst['exactDistance'] ?? 0.0).toDouble();
               double distDiff = (distA - distB).abs();
               if (distDiff < 10.0) { // Menos de 10 metros
                  if (inst['text'].contains('rampa')) {
                     lastInst['text'] = 'Duas passagens com rampa à frente';
                  } else if (inst['text'].contains('Meio-fio')) {
                     lastInst['text'] = 'Dois meios-fios à frente';
                  } else if (inst['text'].contains('Faixa')) {
                     lastInst['text'] = 'Duas faixas de pedestres à frente';
                  }
                  continue; // Pula a inserção desta instrução repetida
               }
            }
         }
         finalInsts.add(inst);
      }
      
      _instructions = finalInsts;
      
      if (_currentRoute.length > 1) {
        final bounds = LatLngBounds.fromPoints(_currentRoute);
        try {
          _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50), maxZoom: 18.0));
        } catch (e) {
          print("Erro ao focar a câmera: $e");
          _mapController.move(_currentRoute.first, 18.0);
        }
      } else if (_currentRoute.isNotEmpty) {
        _mapController.move(_currentRoute.first, 18.0);
      }
    } else {
      _currentRoute = [];
      _routePolylines = [];
      _warningMarkers = [];
      _routeKerbs = [];
      _instructions = [];
    }
  }

  void _startNavigation() {
    if (_instructions.isEmpty) return;
    
    setState(() {
      _mapState = MapState.navigating;
      _currentInstructionIndex = 0;
      _isAutoCentering = true;
      _lastDistanceToNextStep = null;
      _spokenInstructions = {};
    });
    
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 19.0);
    }
    
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((Position pos) {
      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
        if (pos.heading > 0) {
          _currentBearing = pos.heading;
        }
        
        if (_isAutoCentering) {
           _mapController.move(_currentLocation!, 19.0);
           if (_currentBearing > 0) {
             _mapController.rotate(360 - _currentBearing);
           }
        }
      });
      _checkRouteProgress(_currentLocation!);
    });
  }
  
  void _stopNavigation() {
    setState(() {
      _mapState = MapState.routePlanning;
      _isSimulating = false;
      _isAutoCentering = true;
      _currentLocation = _realLocation;
    });
    
    _mapController.rotate(0.0); // Reset map rotation
    if (_startPoint != null) {
      _mapController.move(_startPoint!, 17.0);
    }
    _positionStream?.cancel();
    _positionStream = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _flutterTts.stop(); // Corta a voz imediatamente ao sair
  }
  
  void _startSimulation() {
    if (_currentRoute.isEmpty) return;
    
    // Se o usuário clicar em "iniciar simulação", cancela a navegação real se existir
    _positionStream?.cancel();
    _positionStream = null;
    
    setState(() {
      _mapState = MapState.navigating;
      _currentInstructionIndex = 0;
      _isSimulating = true;
      _isSimulationPaused = true; // Começa pausado
      _simulationRouteIndex = 0;
      _simulationDistanceCovered = 0.0;
      _isAutoCentering = true;
      _lastDistanceToNextStep = null;
      _spokenInstructions = {0};
      _simulationSpeed = 1.0; // Sempre iniciar na velocidade normal
    });
    
    _currentLocation = _currentRoute.first;
    _mapController.move(_currentLocation!, 19.0);
    
    // Parar qualquer voz que estivesse falando antes de recomeçar e dar um pequeno delay
    Future<void> initVoice() async {
      await _flutterTts.stop();
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted && _isSimulating) {
        if (_instructions.isNotEmpty) {
          _speakInstruction(_getSpokenTextForInstruction(_instructions[0]));
        }
      }
    }
    initVoice();
    
    _scheduleSimulationTick();
  }

  void _scheduleSimulationTick() {
    _simulationTimer?.cancel();
    
    // FPS de simulação (~33ms = 30fps)
    const int tickMs = 33; 
    
    _simulationTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      if (!_isSimulating || _currentRoute.isEmpty) {
        timer.cancel();
        return;
      }
      
      if (_isSimulationPaused) return;

      // Velocidade base: ~2.0 m/s (caminhada rápida). Multiplicado pelo speed.
      double speedMps = 2.0 * _simulationSpeed;
      double distanceToMove = speedMps * (tickMs / 1000.0);
      
      _simulationDistanceCovered += distanceToMove;
      
      // Encontrar a coordenada exata com base na distância percorrida
      double accumulatedDistance = 0.0;
      bool reachedEnd = true;
      const Distance distanceCalc = Distance();
      
      for (int i = 0; i < _currentRoute.length - 1; i++) {
        double segmentLength = distanceCalc.as(LengthUnit.Meter, _currentRoute[i], _currentRoute[i + 1]);
        
        if (accumulatedDistance + segmentLength >= _simulationDistanceCovered) {
          // O ponto atual está neste segmento
          double remaining = _simulationDistanceCovered - accumulatedDistance;
          double fraction = remaining / segmentLength;
          
          double lat = _currentRoute[i].latitude + (_currentRoute[i + 1].latitude - _currentRoute[i].latitude) * fraction;
          double lon = _currentRoute[i].longitude + (_currentRoute[i + 1].longitude - _currentRoute[i].longitude) * fraction;
          
          double bearing = distanceCalc.bearing(_currentRoute[i], _currentRoute[i + 1]);
          
          setState(() {
            _currentLocation = LatLng(lat, lon);
            _currentBearing = bearing;
            _simulationRouteIndex = i; // atualizar índice aproximado para outras lógicas
            
            if (_isAutoCentering) {
               _mapController.move(_currentLocation!, 19.0);
               // O mapa não rotaciona mais automaticamente no modo de simulação
            }
          });
          
          _checkRouteProgress(_currentLocation!);
          reachedEnd = false;
          break;
        }
        accumulatedDistance += segmentLength;
      }
      
      if (reachedEnd) {
        timer.cancel();
        setState(() {
           _currentLocation = _currentRoute.last;
           _isSimulating = false;
        });
      }
    });
  }

  void _toggleSimulationSpeed() {
    setState(() {
      if (_simulationSpeed == 1.0) _simulationSpeed = 1.5;
      else if (_simulationSpeed == 1.5) _simulationSpeed = 2.0;
      else if (_simulationSpeed == 2.0) _simulationSpeed = 0.5;
      else _simulationSpeed = 1.0;
    });
  }

  void _restartSimulation() {
    if (!_isSimulating) return;
    
    // Parar qualquer voz que estivesse falando e recomeçar
    _flutterTts.stop();
    if (_instructions.isNotEmpty) {
       Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isSimulating) {
             _speakInstruction(_getSpokenTextForInstruction(_instructions[0]));
          }
       });
    }

    setState(() {
      _simulationRouteIndex = 0;
      _currentInstructionIndex = 0;
      _simulationDistanceCovered = 0.0;
      _isSimulationPaused = false;
      _isAutoCentering = true;
      _spokenInstructions = {0};
      _lastDistanceToNextStep = null;
      if (_currentRoute.isNotEmpty) {
        _currentLocation = _currentRoute.first;
        _mapController.move(_currentLocation!, 19.0);
      }
    });
  }
  
  void _checkRouteProgress(LatLng currentLoc) {
    if (_mapState != MapState.navigating || _currentInstructionIndex >= _instructions.length) return;
    
    final targetInstruction = _instructions[_currentInstructionIndex];
    
    if (targetInstruction['interval'] != null && targetInstruction['interval'].isNotEmpty) {
       int targetPointIndex = targetInstruction['interval'][0];
       
       if (targetPointIndex < _currentRoute.length) {
         LatLng targetPoint = targetInstruction['targetLatLng'] ?? _currentRoute[targetPointIndex];
         
         const Distance distance = Distance();
         final double distToNext = distance(currentLoc, targetPoint);
         
         double displayDistance = distToNext;
         if (targetInstruction['text'] == 'Continue em frente' && targetInstruction['interval'].length > 1) {
             int endIdx = targetInstruction['interval'][1];
             if (endIdx < _currentRoute.length) {
                 displayDistance = distance(currentLoc, _currentRoute[endIdx]);
             }
         }
         
         if (_distanceToNextStep != displayDistance) {
           setState(() {
             _distanceToNextStep = displayDistance;
           });
         }
         
         final double threshold = targetInstruction['trigger_distance'] ?? 15.0;
         
         // Lógica Inteligente de Voz
         if (distToNext <= threshold && !_spokenInstructions.contains(_currentInstructionIndex)) {
            String text = targetInstruction['text'] ?? '';
            String speechText = text;
            if (distToNext > 5.0) {
                speechText = "Em ${distToNext.round()} metros, " + text;
            }
            
            _spokenInstructions.add(_currentInstructionIndex);
            
            // Verifica se a próxima instrução está muito perto desta (menos de 15m)
            if (_currentInstructionIndex + 1 < _instructions.length) {
               final nextInst = _instructions[_currentInstructionIndex + 1];
               if (nextInst['interval'] != null && nextInst['interval'].isNotEmpty) {
                  int nextPointIndex = nextInst['interval'][0];
                  if (nextPointIndex < _currentRoute.length) {
                     LatLng nextTargetPoint = _currentRoute[nextPointIndex];
                     double distBetween = distance(targetPoint, nextTargetPoint);
                     if (distBetween < 15.0) {
                        String distVoice = distBetween > 2.0 ? " em ${distBetween.round()} metros, " : ", ";
                        String distUI = distBetween > 2.0 ? " em ${distBetween.round()}m" : "";
                        
                        String nextText = (nextInst['text'] ?? '').toString();
                        nextText = nextText.replaceAll(RegExp(r'\bii\b', caseSensitive: false), '2')
                                           .replaceAll(RegExp(r'\biii\b', caseSensitive: false), '3')
                                           .replaceAll(RegExp(r'\biv\b', caseSensitive: false), '4')
                                           .replaceAll(RegExp(r'\bvi\b', caseSensitive: false), '6');
                                           
                        String combinedTail = " Depois" + distVoice + nextText.toLowerCase();
                        speechText += combinedTail;
                        
                        // Atualiza a instrução atual para a UI mostrar a combinação
                        setState(() {
                          _instructions[_currentInstructionIndex]['combined_text'] = text + "\n(Depois$distUI: " + nextText.toLowerCase() + ")";
                        });
                        
                        _spokenInstructions.add(_currentInstructionIndex + 1); // Marca como falada para não repetir
                     }
                  }
               }
            }
           
           speechText = speechText.replaceAll(RegExp(r'\bii\b', caseSensitive: false), '2')
                                  .replaceAll(RegExp(r'\biii\b', caseSensitive: false), '3')
                                  .replaceAll(RegExp(r'\biv\b', caseSensitive: false), '4')
                                  .replaceAll(RegExp(r'\bvi\b', caseSensitive: false), '6');
                                  
           _speakInstruction(speechText);
         }
         
         // Condição de ter passado do ponto:
         bool isMovingAway = _spokenInstructions.contains(_currentInstructionIndex) && 
                             _lastDistanceToNextStep != null && 
                             distToNext > _lastDistanceToNextStep! + 0.5 &&
                             distToNext <= threshold;
                             
         bool isPointInstruction = targetInstruction['interval'] != null && 
                                   targetInstruction['interval'].isNotEmpty && 
                                   targetInstruction['interval'].first == targetInstruction['interval'].last;
                                   
         bool hasPassed = isMovingAway || (distToNext <= 5.0 && !isPointInstruction);
                             
         if (hasPassed) {
           setState(() {
              _currentInstructionIndex++;
              _lastDistanceToNextStep = null; // Reseta para o novo target
           });
           return;
         }
         
         _lastDistanceToNextStep = distToNext;
       }
    }
  }
  String _getSpokenTextForInstruction(Map<String, dynamic> inst) {
     String text = inst['text'] ?? '';
     if (text == 'Continue em frente') {
         double dist = inst['distance'] ?? 0.0;
         if (dist > 0) {
             return 'Continue em frente por ${dist.toStringAsFixed(0)} metros';
         }
     }
     return text;
  }

  Future<void> _speakInstruction(String text) async {
    if (_isVoiceMuted) return;
    await _flutterTts.speak(text);
  }
  
  String _formatTime(dynamic timeMs) {
    final mins = (timeMs / 60000).round();
    if (mins < 60) return "$mins min";
    final hours = mins ~/ 60;
    final remainingMins = mins % 60;
    return "$hours h $remainingMins min";
  }
  
  String _formatDistance(dynamic distMeters) {
    if (distMeters < 1000) {
      return "${distMeters.round()} m";
    }
    return "${(distMeters / 1000).toStringAsFixed(1)} km";
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark, // Ícones da barra de status na cor preta
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _campusCenter,
                initialZoom: 17.2,
                minZoom: 14.0,
                maxZoom: 20.0,
                onPositionChanged: (position, hasGesture) {
                  if (_currentZoom != position.zoom) {
                    setState(() {
                      _currentZoom = position.zoom;
                    });
                  }
                  if (hasGesture && _mapState == MapState.navigating) {
                    setState(() {
                      _isAutoCentering = false;
                    });
                  }
                },
                onTap: _onMapTap,
                onLongPress: _onMapLongPress,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.tcc.apposm',
                  maxNativeZoom: 19,
                ),
                PolylineLayer(
                  polylines: _routePolylines.isNotEmpty ? _routePolylines : [
                    if (_currentRoute.isNotEmpty)
                      Polyline(
                        points: _currentRoute,
                        strokeWidth: 6.0,
                        color: Colors.blueAccent.shade700,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (_currentZoom >= 18.2)
                      ..._crosswalks.map((cw) {
                        return Marker(
                          point: LatLng(cw['lat'], cw['lon']),
                          width: 24,
                          height: 24,
                          child: const Icon(Icons.transfer_within_a_station, color: Colors.blue, size: 24),
                        );
                      }).toList(),
                    if (_currentZoom >= 18.0 && _mapState == MapState.routePlanning || _mapState == MapState.navigating)
                      ..._routeKerbs.map((kerb) {
                        bool isRaised = kerb['type'] == 'raised';
                        return Marker(
                          point: LatLng(kerb['lat'], kerb['lon']),
                          width: 26,
                          height: 26,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isRaised ? Icons.warning : Icons.accessible, 
                              color: isRaised ? Colors.red : Colors.green, 
                              size: 20
                            ),
                          ),
                        );
                      }).toList(),
                    if (_startPoint != null && _mapState == MapState.routePlanning)
                      Marker(
                        point: _startPoint!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
                      ),
                    if (_endPoint != null && _mapState != MapState.manualSelection)
                      Marker(
                        point: _endPoint!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    if (_currentLocation != null)
                      Marker(
                        point: _currentLocation!,
                        width: 32,
                        height: 32,
                        child: _mapState == MapState.navigating
                            ? Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade700,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)]
                                ),
                                child: Transform.rotate(
                                  angle: ((_currentBearing - _mapController.camera.rotation) * pi / 180) - (pi / 4),
                                  child: const Icon(Icons.navigation, color: Colors.white, size: 20)
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 4,
                                    )
                                  ]
                                ),
                              ),
                      ),
                  ],
                ),
              ],
            ),
            
            // Barra de Pesquisa (Topo)
            if (_mapState == MapState.defaultView || _mapState == MapState.placeSelected)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () async {
                    final selectedPoi = await showSearch(
                      context: context,
                      delegate: PoiSearchDelegate(pois: _pois, currentLocation: _currentLocation),
                    );
                    
                    if (selectedPoi != null) {
                      if (selectedPoi['type'] == 'manual_selection') {
                        setState(() {
                          if (_startPoint == null) {
                            if (_currentLocation != null) {
                              _startPoint = _currentLocation;
                              _startPointName = "Meu Local";
                            } else {
                              _startPoint = _defaultStartPoint;
                              _startPointName = "Entrada do IF";
                            }
                          }
                          _mapState = MapState.manualSelection;
                          _isSelectingOrigin = false; // está escolhendo destino
                        });
                        return;
                      }

                      setState(() {
                        if (_startPoint == null) {
                          if (_currentLocation != null) {
                            _startPoint = _currentLocation;
                            _startPointName = "Meu Local";
                          } else {
                            _startPoint = _defaultStartPoint;
                            _startPointName = "Entrada do IF";
                          }
                        }
                        _endPoint = LatLng(selectedPoi['lat'], selectedPoi['lon']);
                        _destinationName = selectedPoi['name'];
                        _destinationBuildingName = selectedPoi['parent_name'];
                        if (selectedPoi['is_room'] == true) {
                          _selectedPoi = selectedPoi['parent_poi'];
                          _selectedRoom = selectedPoi;
                        } else {
                          _selectedPoi = selectedPoi;
                          _selectedRoom = null;
                        }
                        _mapState = MapState.placeSelected;
                        _currentRoute = [];
_routePolylines = [];
_warningMarkers = [];
                      });
                      _mapController.move(_endPoint!, 17.0);
                    }
                  },
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/if_logo.png',
                            width: 36,
                            height: 36,
                            errorBuilder: (context, error, stackTrace) => 
                              const CircleAvatar(
                                backgroundColor: Colors.green, 
                                child: Icon(Icons.school, color: Colors.white, size: 20)
                              ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "Pesquisar aqui",
                            style: TextStyle(fontSize: 16, color: Colors.black54),
                          ),
                        ),
                        const Icon(Icons.mic, color: Colors.black54),
                        const SizedBox(width: 16),
                      ],
                    ),
                  ),
                ),
              ),
              
            // Painel Superior: Planejamento de Rotas
            if (_mapState == MapState.routePlanning)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 10,
                    right: 10,
                    bottom: 10,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () {
                              setState(() {
                                _mapState = MapState.defaultView;
                                _currentRoute = [];
_routePolylines = [];
_warningMarkers = [];
                                _endPoint = null;
                              });
                            },
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: () => _selectPoint(isOrigin: true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade300)
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.my_location, size: 18, color: Colors.blue),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(_startPointName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600))),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => _selectPoint(isOrigin: false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade300)
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.location_on, size: 18, color: Colors.red),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _destinationName.isEmpty ? "Escolher destino" : _destinationName,
                                            maxLines: 1, 
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _destinationName.isEmpty ? Colors.black54 : Colors.black,
                                              fontWeight: _destinationName.isEmpty ? FontWeight.normal : FontWeight.w600,
                                            )
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.swap_vert),
                            onPressed: _swapPoints,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Lista horizontal de perfis distribuída uniformemente
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _profileData.map((profile) {
                            final pid = profile['id'] as String;
                            final isSelected = pid == _selectedProfile;
                            
                            String timeText = "...";
                            if (!_isCalculatingRoutes && _routeResults.containsKey(pid)) {
                              timeText = _formatTime(_routeResults[pid]!['time']);
                            } else if (!_isCalculatingRoutes) {
                              timeText = "N/A";
                            }
                            
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedProfile = pid;
                                    _applySelectedRoute();
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? Colors.blue : Colors.grey.shade300,
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(profile['icon'], size: 22, color: isSelected ? Colors.blue : Colors.grey.shade700),
                                      const SizedBox(height: 4),
                                      Text(
                                        profile['label'], 
                                        style: TextStyle(
                                          color: isSelected ? Colors.blue : Colors.grey.shade800, 
                                          fontSize: 10, 
                                          fontWeight: FontWeight.bold
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        timeText,
                                        style: TextStyle(
                                          color: isSelected ? Colors.blue : Colors.grey.shade800,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
            // Overlay para seleção manual no centro da tela
            if (_mapState == MapState.manualSelection)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 40), // compensar o bico do pino no centro exato
                  child: Icon(
                    Icons.location_on, 
                    size: 50, 
                    color: _isSelectingOrigin ? Colors.blue : Colors.red,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 5))],
                  ),
                ),
              ),

            // Botão Confirmar Local no modo de seleção manual
            if (_mapState == MapState.manualSelection)
              Positioned(
                bottom: 30,
                left: 16,
                right: 16,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 5,
                  ),
                  onPressed: () {
                    final center = _mapController.camera.center;
                    
                    // Verificar limite de 1.3km
                    final dist = const Distance().as(LengthUnit.Meter, _campusCenter, center);
                    if (dist > 1300.0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("O local deve estar dentro do campus do IF Goiano."),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    setState(() {
                      final poi = _getNearestPoi(center);
                      if (_isSelectingOrigin) {
                        if (poi != null) {
                          _startPoint = LatLng(poi['lat'], poi['lon']);
                          _startEntrances = _getEntrancesForPoi(poi);
                          _startPointName = poi['name'];
                        } else {
                          _startPoint = center;
                          _startEntrances = [{'lat': center.latitude, 'lon': center.longitude}];
                          _startPointName = "${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}";
                        }
                        
                        _mapState = MapState.routePlanning;
                        if (_startPoint != null && _endPoint != null) {
                          _calculateAllRoutes();
                        }
                      } else {
                        if (poi != null) {
                          _endPoint = LatLng(poi['lat'], poi['lon']);
                          _endEntrances = _getEntrancesForPoi(poi);
                          _destinationName = poi['name'];
                          _selectedPoi = poi;
                          _destinationBuildingName = null;
                        } else {
                          _endPoint = center;
                          _endEntrances = [{'lat': center.latitude, 'lon': center.longitude}];
                          _destinationName = "${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}";
                          _selectedPoi = null;
                          _destinationBuildingName = null;
                        }
                        
                        _selectedRoom = null;
                        _mapState = MapState.placeSelected;
                        _currentRoute = [];
                        _routePolylines = [];
                        _warningMarkers = [];
                      }
                    });
                  },
                  child: const Text("Confirmar Local", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),

            // Instrução de navegação
            if (_mapState == MapState.navigating && _instructions.isNotEmpty)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 16,
                right: 16,
                child: Builder(
                  builder: (context) {
                    int safeIndex = _currentInstructionIndex < _instructions.length ? _currentInstructionIndex : _instructions.length - 1;
                    var currentInst = _instructions[safeIndex];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade800,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.directions, color: Colors.white, size: 40),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_distanceToNextStep > 0)
                                  Text(
                                    "Em ${_distanceToNextStep.round()}m",
                                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                Text(
                                  currentInst['combined_text'] ?? currentInst['text'] ?? '',
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                ),
              ),
              
            // Bússola durante navegação
            if (_mapState == MapState.navigating)
               Positioned(
                 top: MediaQuery.of(context).padding.top + 100,
                 right: 16,
                 child: FloatingActionButton(
                   heroTag: 'compassNavBtn',
                   mini: true,
                   backgroundColor: Colors.white,
                   onPressed: () {
                     setState(() {
                       _mapController.rotate(0);
                       _isAutoCentering = false; // Parar de seguir a rotação automática se ele resetar o norte
                     });
                   },
                   child: const Icon(Icons.explore, color: Colors.black54),
                 ),
               ),
               
            // Botão Recentralizar Câmera
            if (_mapState == MapState.navigating && !_isAutoCentering)
               Positioned(
                 bottom: 120,
                 right: 16,
                 child: FloatingActionButton.extended(
                   heroTag: 'recenterBtn',
                   backgroundColor: Colors.blue.shade700,
                   onPressed: () {
                     setState(() {
                       _isAutoCentering = true;
                       if (_currentLocation != null) {
                         _mapController.move(_currentLocation!, 19.0);
                         if (_currentBearing > 0) {
                           _mapController.rotate(360 - _currentBearing);
                         }
                       }
                     });
                   },
                   icon: const Icon(Icons.my_location, color: Colors.white),
                   label: const Text("Recentralizar", style: TextStyle(color: Colors.white)),
                 ),
               ),
               
            // Painel Arrastável Inferior
            if (_mapState == MapState.navigating)
              DraggableScrollableSheet(
                initialChildSize: 0.25,
                minChildSize: 0.25,
                maxChildSize: 0.7,
                builder: (context, scrollController) {
                  var profile = _profileData.firstWhere((p) => p['id'] == _selectedProfile);
                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        children: [
                          // Alça de arrastar
                          Container(
                            margin: const EdgeInsets.only(top: 8, bottom: 4),
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          // Cabeçalho fixo
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const SizedBox(width: 40), // Balance left side so the center is truly centered
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _routeResults[_selectedProfile]?['time'] != null 
                                                ? _formatTime(_routeResults[_selectedProfile]!['time']) 
                                                : '--',
                                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(profile['icon'], color: Colors.grey.shade600, size: 20),
                                        ],
                                      ),
                                      Text(
                                        _routeResults[_selectedProfile]?['distance'] != null 
                                            ? _formatDistance(_routeResults[_selectedProfile]!['distance']) 
                                            : '--',
                                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                FloatingActionButton(
                                  heroTag: 'closeNavBtn',
                                  mini: true,
                                  backgroundColor: Colors.red.shade100,
                                  elevation: 0,
                                  onPressed: _stopNavigation,
                                  child: const Icon(Icons.close, color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          // Lista de instruções rolável
                          ListView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(16),
                            itemCount: _instructions.length,
                            itemBuilder: (context, index) {
                              bool isPassed = index < _currentInstructionIndex;
                              bool isCurrent = index == _currentInstructionIndex;
                              
                              return ListTile(
                                leading: Icon(
                                  Icons.turn_right, // ícone genérico, poderia parsear dependendo da instrução
                                  color: isCurrent ? Colors.blue : (isPassed ? Colors.grey : Colors.black87),
                                ),
                                title: Text(
                                  _instructions[index]['text'] ?? '',
                                  style: TextStyle(
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    color: isCurrent ? Colors.blue : (isPassed ? Colors.grey : Colors.black87),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
               
            // Botão de iniciar simulação
            if (_mapState == MapState.routePlanning && _currentRoute.isNotEmpty)
              Positioned(
                top: MediaQuery.of(context).padding.top + 230,
                left: 16,
                child: FloatingActionButton(
                  heroTag: 'simulateBtn',
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: _startSimulation,
                  child: const Icon(Icons.directions_walk, color: Colors.purple),
                ),
              ),

            // Controles da simulação
            if (_isSimulating && _mapState == MapState.navigating)
              Positioned(
                top: MediaQuery.of(context).padding.top + 230,
                left: 16,
                child: Column(
                  children: [
                    FloatingActionButton(
                      heroTag: 'simRestartBtn',
                      mini: true,
                      backgroundColor: Colors.white,
                      onPressed: _restartSimulation,
                      child: const Icon(Icons.replay, color: Colors.blue),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'simPauseBtn',
                      mini: true,
                      backgroundColor: Colors.white,
                      onPressed: () {
                        setState(() {
                          _isSimulationPaused = !_isSimulationPaused;
                        });
                      },
                      child: Icon(_isSimulationPaused ? Icons.play_arrow : Icons.pause, color: Colors.blue),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'simSpeedBtn',
                      mini: true,
                      backgroundColor: Colors.white,
                      onPressed: _toggleSimulationSpeed,
                      child: Text("${_simulationSpeed}x", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12)),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'simVoiceBtn',
                      mini: true,
                      backgroundColor: Colors.white,
                      onPressed: () {
                        setState(() {
                          _isVoiceMuted = !_isVoiceMuted;
                        });
                        if (_isVoiceMuted) {
                          _flutterTts.stop();
                        }
                      },
                      child: Icon(_isVoiceMuted ? Icons.volume_off : Icons.volume_up, color: _isVoiceMuted ? Colors.red : Colors.blue),
                    ),
                  ],
                ),
              ),

            // Botões da direita (Bússola e Localização Atual)
            if (_mapState != MapState.navigating && _mapState != MapState.routePlanning && _mapState != MapState.manualSelection)
              Positioned(
                top: MediaQuery.of(context).padding.top + 80,
                right: 16,
                child: Column(
                  children: [
                    FloatingActionButton(
                      heroTag: 'compassBtn',
                      mini: true,
                      backgroundColor: Colors.white,
                      onPressed: () {
                        _mapController.rotate(0.0);
                      },
                      child: const Icon(Icons.explore, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'myLocBtn',
                      mini: true,
                      backgroundColor: Colors.white,
                      onPressed: () {
                        if (_currentLocation != null) {
                           _mapController.move(_currentLocation!, 17.0);
                        }
                      },
                      child: const Icon(Icons.my_location, color: Colors.blue),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'feedbackBtn',
                      mini: true,
                      backgroundColor: Colors.yellow.shade700,
                      onPressed: () => _showFeedbackDialog(),
                      child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
              
            if (_mapState == MapState.defaultView)
              Positioned(
                bottom: 30,
                right: 16,
                child: FloatingActionButton(
                  heroTag: 'routesModeBtn',
                  backgroundColor: Colors.blue.shade700,
                  onPressed: () {
                    setState(() {
                      if (_currentLocation != null) {
                        _startPoint = _currentLocation;
                        _startPointName = "Meu Local";
                      } else {
                        _startPoint = _defaultStartPoint;
                        _startPointName = "Entrada do IF";
                      }
                      _endPoint = null;
                      _destinationName = "";
                      _currentRoute = [];
                      _routePolylines = [];
                      _warningMarkers = [];
                      _routeResults.clear();
                      _mapState = MapState.routePlanning;
                    });
                  },
                  child: const Icon(Icons.directions, color: Colors.white),
                ),
              ),
                      // Bottom Sheet: Local Selecionado
            if (_mapState == MapState.placeSelected)
              Positioned.fill(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.35,
                  minChildSize: 0.20,
                  maxChildSize: 0.6,
                  builder: (context, scrollController) {
                    final hasRooms = _selectedPoi != null && _selectedPoi!['rooms'] != null && (_selectedPoi!['rooms'] as List).isNotEmpty;
                    int validRoomsCount = 0;
                    if (hasRooms) {
                      validRoomsCount = (_selectedPoi!['rooms'] as List).where((r) {
                        final tag = r['tag']?.toString().toLowerCase() ?? '';
                        final name = r['name']?.toString().toLowerCase() ?? '';
                        
                        if (name.contains('banheiro') || tag == 'toilet' || tag == 'kitchen' || name.contains('kitchen') || name.contains('copa')) {
                          return false;
                        }
                        return true;
                      }).length;
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
                      ),
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: [
                          const SizedBox(height: 10),
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _destinationName.isNotEmpty ? _destinationName : "Local Selecionado",
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _mapState = MapState.defaultView;
                                      _endPoint = null;
                                      _currentRoute = [];
                                      _routePolylines = [];
                                      _warningMarkers = [];
                                      
                                      // Reseta o local de inicio ao fechar
                                      if (_currentLocation != null) {
                                        _startPoint = _currentLocation;
                                        _startPointName = "Meu Local";
                                      } else {
                                        _startPoint = _defaultStartPoint;
                                        _startPointName = "Entrada do IF";
                                      }
                                    });
                                  },
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.red, width: 1.5),
                                      color: Colors.red.shade50,
                                    ),
                                    child: const Icon(Icons.close, color: Colors.red, size: 20),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Text(
                            "Rio Verde - GO",
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                                  ),
                                  icon: const Icon(Icons.directions),
                                  label: const Text("Rotas", style: TextStyle(fontSize: 16)),
                                  onPressed: () {
                                    setState(() {
                                      _mapState = MapState.routePlanning;
                                    });
                                    _calculateAllRoutes();
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade600,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                                  ),
                                  icon: const Icon(Icons.navigation),
                                  label: const Text("Iniciar", style: TextStyle(fontSize: 16)),
                                  onPressed: () async {
                                    await _calculateAllRoutes();
                                    if (_currentRoute.isNotEmpty) _startNavigation();
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (hasRooms) ...[
                            const Divider(),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${validRoomsCount > 0 ? '$validRoomsCount ' : ''}Salas neste local:", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                                  const Text("Escolha a que deseja ir", style: TextStyle(fontSize: 14, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                children: (_selectedPoi!['rooms'] as List).map((room) {
                                  final isSelected = _selectedRoom == room;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.blue.shade50 : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? Colors.blue.shade400 : Colors.grey.shade200,
                                        width: isSelected ? 2.0 : 1.0,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                                      leading: Icon(
                                        room['name'].toString().toLowerCase().contains('banheiro') ? Icons.wc : Icons.meeting_room,
                                        color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600,
                                      ),
                                      title: Text(
                                        room['name'],
                                        style: TextStyle(
                                          color: isSelected ? Colors.blue.shade800 : Colors.black87,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        ),
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _selectedRoom = room;
                                          _endPoint = LatLng(room['lat'], room['lon']);
                                          _destinationName = room['name'];
                                          _destinationBuildingName = _selectedPoi?['name'];
                                        });
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ]
                        ],
                      ),
                    );
                  },
                ),
              ),
            // Bottom Sheet: Detalhes da Rota (Apenas no Planejamento)
            if (_mapState == MapState.routePlanning && (_isCalculatingRoutes || _routeResults.isNotEmpty || (_startPoint != null && _endPoint != null)))
              Positioned.fill(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.35,
                  minChildSize: 0.20,
                  maxChildSize: 0.6,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
                      ),
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: [
                          const SizedBox(height: 10),
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isCalculatingRoutes)
                            const Padding(
                              padding: EdgeInsets.all(20.0),
                              child: CircularProgressIndicator(),
                            )
                          else if (_routeResults.containsKey(_selectedProfile))
                            ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.baseline,
                                              textBaseline: TextBaseline.alphabetic,
                                              children: [
                                                Text(
                                                  _formatTime(_routeResults[_selectedProfile]!['time']),
                                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  "(${_formatDistance(_routeResults[_selectedProfile]!['distance'])})",
                                                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                                                ),
                                              ],
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  if (_currentLocation != null) {
                                                    _startPoint = _currentLocation;
                                                    _startPointName = "Meu Local";
                                                  } else {
                                                    _startPoint = _defaultStartPoint;
                                                    _startPointName = "Entrada do IF";
                                                  }
                                                  
                                                  _endPoint = null;
                                                  _destinationName = "";
                                                  _currentRoute = [];
                                                  _routePolylines = [];
                                                  _warningMarkers = [];
                                                  _routeResults.clear();
                                                  _mapState = MapState.defaultView;
                                                });
                                              },
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.red, width: 1.5),
                                                  color: Colors.red.shade50,
                                                ),
                                                child: const Icon(Icons.close, color: Colors.red, size: 20),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        const Text("Trajeto mais rápido", style: TextStyle(color: Colors.black54)),
                                        const SizedBox(height: 20),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue.shade700,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                            ),
                                            icon: const Icon(Icons.navigation),
                                            label: const Text("Iniciar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                            onPressed: _startNavigation,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        const Text("Passo a passo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                                        const SizedBox(height: 10),
                                      ],
                                    ),
                                  ),
                                  ..._instructions.map((inst) {
                                    bool isShared = inst['isSharedRoad'] == true;
                                    return Container(
                                      color: isShared ? Colors.yellow.shade100 : Colors.transparent,
                                      child: ListTile(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                              leading: Icon(
                                                isShared ? Icons.warning_amber_rounded : Icons.turn_right, 
                                                color: isShared ? Colors.orange.shade800 : Colors.black
                                              ),
                                              title: Text(
                                                inst['text'] ?? '', 
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w500, 
                                                  color: isShared ? Colors.orange.shade900 : Colors.black
                                                )
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (inst['isCustom'] != true)
                                                    Text(_formatDistance(inst['distance'] ?? 0), style: TextStyle(color: isShared ? Colors.orange.shade800 : Colors.black)),
                                                  if (isShared)
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 4.0),
                                                      child: Text("Atenção: Trecho sem calçada.", style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.bold)),
                                                    )
                                                ],
                                              ),
                                            ),
                                          );
                                  }).toList(),
                                  const SizedBox(height: 20),
                            ]
                          else
                            const Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Text("Rota indisponível para este perfil ou locais fora do mapa.", style: TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PoiSearchDelegate extends SearchDelegate {
  final List<dynamic> pois;
  final LatLng? currentLocation;
  late final List<dynamic> _flatPois;
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  bool _isMicVisible = true;
  Timer? _blinkTimer;

  PoiSearchDelegate({required this.pois, this.currentLocation}) {
    _flatPois = [];
    for (var poi in pois) {
      _flatPois.add(poi);
      if (poi['rooms'] != null) {
        for (var room in poi['rooms']) {
          final roomCopy = Map<String, dynamic>.from(room);
          roomCopy['is_room'] = true;
          roomCopy['parent_name'] = poi['name'];
          roomCopy['parent_poi'] = poi;
          _flatPois.add(roomCopy);
        }
      }
    }
  }

  @override
  String get searchFieldLabel => 'Pesquise aqui';

  String _normalize(String str) {
    var withDia = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    var withoutDia = 'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';
    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], withoutDia[i]);
    }
    str = str.toLowerCase();
    
    // Remove zeros à esquerda de números isolados (ex: 01 -> 1, 005 -> 5) para bater as buscas corretamente
    str = str.replaceAllMapped(RegExp(r'\b0+(\d+)\b'), (match) => match.group(1)!);
    
    return str;
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      StatefulBuilder(
        builder: (context, setState) {
          return IconButton(
            icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? (_isMicVisible ? Colors.red : Colors.red.withOpacity(0.3)) : null),
            onPressed: () async {
              if (!_isListening) {
                bool available = await _speechToText.initialize(
                  onStatus: (status) {
                    if (status == 'done' || status == 'notListening') {
                      _blinkTimer?.cancel();
                      setState(() {
                        _isListening = false;
                        _isMicVisible = true;
                      });
                    }
                  },
                  onError: (errorNotification) {
                    _blinkTimer?.cancel();
                    setState(() {
                      _isListening = false;
                      _isMicVisible = true;
                    });
                  },
                );
                if (available) {
                  setState(() {
                    _isListening = true;
                    _isMicVisible = true;
                  });
                  _blinkTimer?.cancel();
                  _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
                    if (!_speechToText.isListening) {
                      timer.cancel();
                      setState(() {
                        _isListening = false;
                        _isMicVisible = true;
                      });
                      return;
                    }
                    setState(() => _isMicVisible = !_isMicVisible);
                  });
                  _speechToText.listen(
                    onResult: (result) {
                      if (_isListening) {
                        String recognized = result.recognizedWords;
                        recognized = recognized.replaceAll(RegExp(r'\bfala\b', caseSensitive: false), 'sala');
                        
                        Map<String, String> wordToNumber = {
                          r'\bum\b': '1',
                          r'\bdois\b': '2',
                          r'\btrês\b': '3',
                          r'\btres\b': '3',
                          r'\bquatro\b': '4',
                          r'\bcinco\b': '5',
                          r'\bseis\b': '6',
                          r'\bsete\b': '7',
                          r'\boito\b': '8',
                          r'\bnove\b': '9',
                          r'\bdez\b': '10',
                        };
                        wordToNumber.forEach((word, number) {
                          recognized = recognized.replaceAll(RegExp(word, caseSensitive: false), number);
                        });
                        
                        recognized = recognized.replaceAllMapped(RegExp(r'\b([a-zA-Z](?:\s+[a-zA-Z])+)\b'), (match) {
                          return match.group(1)!.replaceAll(RegExp(r'\s+'), '').toUpperCase();
                        });

                        query = recognized;
                      }
                    },
                    localeId: 'pt_BR',
                    pauseFor: const Duration(seconds: 5),
                  );
                }
              } else {
                _blinkTimer?.cancel();
                setState(() {
                  _isListening = false;
                  _isMicVisible = true;
                });
                _speechToText.stop();
              }
            },
          );
        },
      ),
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          _blinkTimer?.cancel();
          _isListening = false;
          _speechToText.stop();
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildList();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildList();
  }

  Widget _buildList() {
    final normalizedQuery = _normalize(query);
    final suggestions = query.isEmpty
        ? _flatPois
        : _flatPois.where((poi) {
            final name = _normalize(poi['name']?.toString() ?? '');
            final shortName = _normalize(poi['short_name']?.toString() ?? '');
            final altName = _normalize(poi['alt_name']?.toString() ?? '');
            final parentName = _normalize(poi['parent_name']?.toString() ?? '');
            final description = _normalize(poi['description']?.toString() ?? '');
            
            return name.contains(normalizedQuery) || 
                   shortName.contains(normalizedQuery) || 
                   altName.contains(normalizedQuery) ||
                   parentName.contains(normalizedQuery) ||
                   description.contains(normalizedQuery);
          }).toList();

    return ListView.builder(
      itemCount: suggestions.length + 1, // +1 para opção de escolher no mapa
      itemBuilder: (context, index) {
        if (index == 0) {
          // A primeira opção sempre é "Escolher no mapa"
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.place, color: Colors.blue),
            ),
            title: const Text("📍 Escolha o local", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            onTap: () {
              close(context, {'type': 'manual_selection', 'name': 'Local no mapa'});
            },
          );
        }
        
        final poi = suggestions[index - 1]; // ajusta o índice para a lista
        
        String subtitleText = "";
        if (poi['is_room'] == true) {
          subtitleText = "Sala em: ${poi['parent_name']} ";
        }
        if (currentLocation != null) {
           final dist = const Distance().as(LengthUnit.Meter, currentLocation!, LatLng(poi['lat'], poi['lon']));
           if (dist < 1000) {
             subtitleText += "(${dist.round()} m)";
           } else {
             subtitleText += "(${(dist / 1000).toStringAsFixed(1)} km)";
           }
        }
        subtitleText = subtitleText.trim();

        if (poi['short_name'] != null && poi['short_name'].toString().trim().isNotEmpty) {
          if (subtitleText.isNotEmpty) subtitleText += "\n";
          subtitleText += "Sigla: ${poi['short_name']}";
        }

        if (poi['alt_name'] != null && poi['alt_name'].toString().trim().isNotEmpty) {
          if (subtitleText.isNotEmpty) subtitleText += "\n";
          subtitleText += "Nome alternativo: ${poi['alt_name']}";
        }
        
        return ListTile(
          isThreeLine: subtitleText.split('\n').length > 1,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              poi['is_room'] == true 
                  ? (poi['name'].toString().toLowerCase().contains('banheiro') ? Icons.wc : Icons.meeting_room)
                  : (poi['type'] == 'way' ? Icons.business : Icons.room),
              color: Colors.black54,
            ),
          ),
          title: Text(poi['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: subtitleText.isNotEmpty ? Text(subtitleText) : null,
          onTap: () {
            close(context, poi);
          },
        );
      },
    );
  }
}

class WarningTriangle extends StatelessWidget {
  const WarningTriangle({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(32, 32),
      painter: _WarningTrianglePainter(),
    );
  }
}

class _WarningTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = ui.Path();
    path.moveTo(size.width / 2, 2);
    path.lineTo(size.width - 2, size.height - 4);
    path.lineTo(2, size.height - 4);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);

    // Draw exclamation mark
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '!',
        style: TextStyle(
          color: Colors.black,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2 + 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
