import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mapacampus/screens/blocos.dart';


class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  
  final List<Marker> _markers = [];
  Marker? _currentLocationMarker;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _searchQuery = '';
  StreamSubscription<Position>? _positionStream;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isDistanceCalculated = false;
  String? _selectedBloco;
  String _displayDistance = '';
  double _lastSpokenDistance = 0;
  Timer? _distanceCheckTimer;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _addBlocoMarkers();
    _speech = stt.SpeechToText();
    _initializeTts();
    _provideAccessibilityDescriptions();
    _announceMapLoaded();
  }

  void _initializeTts() {
    _flutterTts.setLanguage("pt-BR");
    _flutterTts.setSpeechRate(0.4);
    _flutterTts.setPitch(1.0);
  }

void _getCurrentLocation() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition();
      _positionStream = Geolocator.getPositionStream().listen((Position position) {
        setState(() {
          _currentPosition = position;
        });
        _updateCurrentLocationMarker();
        _checkDistanceToBloco();
      });
    } catch (e) {
      print("Erro ao obter a localização: $e");
    }
  }


  void _updateCurrentLocationMarker() {
    if (_currentPosition != null) {
      setState(() {
        _currentLocationMarker = Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        );
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ),
      );
    }
  }

void _addBlocoMarkers() {
  for (var bloco in blocos) {
    _markers.add(
      Marker(
        markerId: MarkerId(bloco['nome']),
        position: LatLng(bloco['latitude'], bloco['longitude']),
        infoWindow: InfoWindow(
          title: bloco['nome'],
          snippet: bloco['descricao'],
          onTap: () {
            _speak("Descrição do bloco ${bloco['nome']}: ${bloco['descricao']}");
          },
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
    );
  }
}


  void _speak(String text) async {
    await _flutterTts.speak(text);
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _searchQuery = val.recognizedWords;
              _findAndSpeakBloco(_searchQuery);
            });
          },
          localeId: 'pt_BR',
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

void _findAndSpeakBloco(String query) {
  final matchedBloco = blocos.firstWhere(
    (bloco) => bloco['nome'].toLowerCase().contains(query.toLowerCase()),
    orElse: () => {},
  );

  if (matchedBloco.isNotEmpty) {
    _selectedBloco = matchedBloco['nome'];
    _announceSelectedBloco();
    _calculateDistanceToBloco();
    
    setState(() {
      _markers.clear();
      for (var bloco in blocos) {
        BitmapDescriptor icon = bloco['nome'] == _selectedBloco
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);

        _markers.add(
          Marker(
            markerId: MarkerId(bloco['nome']),
            position: LatLng(bloco['latitude'], bloco['longitude']),
            infoWindow: InfoWindow(
              title: bloco['nome'],
              snippet: bloco['descricao'],
              onTap: () {
                _speak("Você selecionou o ${bloco['nome']}. ${bloco['descricao']}");
              },
            ),
            icon: icon,
          ),
        );
      }
    });
  } else {
    _speak("Nenhum bloco encontrado para a busca: $query");
  }
}

  void _calculateDistanceToBloco() {
    if (_currentPosition != null && _selectedBloco != null) {
      final selected = blocos.firstWhere((bloco) => bloco['nome'] == _selectedBloco);
      double distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        selected['latitude'],
        selected['longitude'],
      );

      setState(() {
        _isDistanceCalculated = true;
        _displayDistance = "A distância até o ${selected['nome']} é de ${distanceInMeters.toStringAsFixed(2)} metros.";
        _lastSpokenDistance = distanceInMeters;
      });

      _speak(_displayDistance);
    }
  }

  void _checkDistanceToBloco() {
    if (_currentPosition != null && _selectedBloco != null) {
      final selected = blocos.firstWhere((bloco) => bloco['nome'] == _selectedBloco);
      double distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        selected['latitude'],
        selected['longitude'],
      );

      if (distanceInMeters < 100) {
        // Avisar a cada 10 metros quando estiver a menos de 100 metros
        if (distanceInMeters < 50 && _lastSpokenDistance >= 50) {
          _speak("Você está a menos de 50 metros do ${selected['nome']}. Prepare-se para chegar.");
        } else if (distanceInMeters < 100 && (distanceInMeters - _lastSpokenDistance).abs() >= 10) {
          _speak("Você está a ${distanceInMeters.toStringAsFixed(2)} metros do ${selected['nome']}.");
          _lastSpokenDistance = distanceInMeters; // Atualiza a última distância falada
        }
      } else if (distanceInMeters >= 100 && (distanceInMeters - _lastSpokenDistance).abs() >= 50) {
        // Avisar a cada 50 metros quando estiver a mais de 100 metros
        _speak("Você está a ${distanceInMeters.toStringAsFixed(2)} metros do ${selected['nome']}.");
        _lastSpokenDistance = distanceInMeters; // Atualiza a última distância falada
      }
    }
  }

void _provideAccessibilityDescriptions() {
  _speak(
    "Bem-vindo ao mapa do campus. Use o campo de busca ou o botão de microfone para procurar um bloco específico."
  );
}

// Função para fornecer feedback ao interagir com o campo de busca.
void _announceSearchField() {
  _speak("Digite ou diga o nome do bloco que deseja encontrar.");
}

// Função para anunciar a seleção de bloco.
void _announceSelectedBloco() {
  if (_selectedBloco != null) {
    _speak("Você está procurando pelo $_selectedBloco. Aguarde as instruções de distância.");
  }
}

/// Função para fornecer descrição detalhada ao iniciar o Google Maps.
void _announceMapLoaded() {
  _speak("O mapa foi carregado. Você verá os blocos destacados em azul. Use o microfone para busca por voz ou digite o nome de um bloco no campo de pesquisa.");
}

  @override
  void dispose() {
    _positionStream?.cancel();
    _speech.stop();
    _distanceCheckTimer?.cancel();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Mapa do Campus'),
    ),
    body: _currentPosition == null
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              GoogleMap(
                onMapCreated: (controller) {
                  setState(() {
                    _mapController = controller;
                  });
                },
                initialCameraPosition: CameraPosition(
                  target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  zoom: 17,
                ),
                markers: Set<Marker>.of(_markers)..add(_currentLocationMarker!),
              ),
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Card(
                  elevation: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onTap: _announceSearchField, // Chama a função ao tocar no campo de busca
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                            decoration: const InputDecoration(
                              hintText: 'Digite o bloco desejado',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () {
                            _findAndSpeakBloco(_searchQuery);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isDistanceCalculated)
                Positioned(
                  bottom: 100, 
                  left: 10,
                  right: 10,
                  child: Card(
                    color: Colors.white,
                    elevation: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        _displayDistance,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 10,
                left: MediaQuery.of(context).size.width / 2 - 35, // Centraliza o botão
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: FloatingActionButton(
                    onPressed: _listen,
                    child: const Icon(Icons.mic, size: 36),
                  ),
                ),
              ),
            ],
          ),
  );
}
}
