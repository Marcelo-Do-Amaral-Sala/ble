import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MaterialApp(home: HomePage()));
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Variables de estado
  bool _foundDeviceWaitingToConnect = false;
  bool _scanStarted = false;
  bool _scanFinished = false;
  bool _connected = false;

  // Variables relacionadas con Bluetooth
  late DiscoveredDevice _ubiqueDevice;
  final flutterReactiveBle = FlutterReactiveBle();
  late StreamSubscription<DiscoveredDevice> _scanStream;

  // Lista de UUIDs de servicios que queremos detectar
  List<Uuid> serviceUuids = [
    Uuid.parse("49535343-FE7D-4AE5-8FA9-9FAFD205E455"), // Ejemplo de UUID de servicio
    Uuid.parse("49535343-8841-43F4-A8D4-ECBE34729BB4"), // Otro UUID de servicio
    Uuid.parse("49535343-1E4D-4BD9-BA61-23C647249617"), // Otro UUID de servicio
  ];


  String targetDeviceId =
      "F4:12:FA:EC:C5:65"; // El ID del dispositivo que estamos buscando
  String targetDeviceName =
      "IM5-C565"; // El nombre del dispositivo que estamos buscando
  String targetServiceUuid = "49535343-FE7D-4AE5-8FA9-9FAFD205E455";

  // Variables para los retos y respuestas
  List<int> challenge = [0x00, 0x00, 0x00, 0x00]; // Valor inicial de los retos
  List<int> response = [0x00, 0x00, 0x00, 0x00]; // Respuesta a los retos

// Función para generar el reto
  List<int> generateChallengeResponse(List<int> challenge) {
    return [
      challenge[0] ^ 0x2A, // R-H1 = H1 xor 0x2A
      challenge[1] ^ 0x55, // R-H2 = H2 xor 0x55
      challenge[2] ^ 0xAA, // R-H3 = H3 xor 0xAA
      challenge[3] ^ 0xA2, // R-H4 = H4 xor 0xA2
    ];
  }

  @override
  void initState() {
    super.initState();
    // Iniciar escaneo automáticamente, conectarse y ejecutar el protocolo de seguridad
    _startScan();
  }

  // Iniciar el escaneo
  void _startScan() async {
    if (kDebugMode) {
      print("Iniciando el escaneo...");
    }
    bool permGranted = false;
    setState(() {
      _scanStarted = true;
      _scanFinished = false;
    });

    // Solicitar permisos de ubicación en Android/iOS
    if (Platform.isAndroid || Platform.isIOS) {
      if (kDebugMode) {
        print("Solicitando permisos de ubicación...");
      }
      PermissionStatus permission = await Permission.location.request();
      if (permission == PermissionStatus.granted) {
        permGranted = true;
        if (kDebugMode) {
          print("Permiso de ubicación concedido.");
        }
      } else {
        // Mostrar mensaje si no se otorgan permisos
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Se requieren permisos de ubicación")),
        );
        if (kDebugMode) {
          print("Permiso de ubicación denegado.");
        }
      }
    }

    // Iniciar el escaneo solo si los permisos están otorgados
    if (permGranted) {
      if (kDebugMode) {
        print("Iniciando escaneo BLE...");
      }
      _scanStream =
          flutterReactiveBle.scanForDevices(withServices: [], scanMode: ScanMode.lowLatency).listen((device) {
        if (kDebugMode) {
          print("Dispositivo encontrado: ${device.name}, ID: ${device.id}");
        }

        // Verificar si el ID o el nombre del dispositivo es el que estamos buscando
        if (device.id == targetDeviceId || device.name == targetDeviceName) {
          if (kDebugMode) {
            print("Dispositivo encontrado: ${device.name}, ID: ${device.id}");
          }
          setState(() {
            _ubiqueDevice = device;
            _foundDeviceWaitingToConnect = true;
            _scanStarted = false;
            _scanFinished = true;
          });

          // Detener el escaneo una vez que se encuentra el dispositivo
          _scanStream.cancel();
          if (kDebugMode) {
            print("Escaneo detenido.");
          }
          _connectToDevice();
        }
      });
    }
  }

  // Conectar al dispositivo
  void _connectToDevice() async {
    if (kDebugMode) {
      print("Conectando al dispositivo...");
    }
    // Conectar al dispositivo BLE
    Stream<ConnectionStateUpdate> currentConnectionStream = flutterReactiveBle
        .connectToAdvertisingDevice(
            id: _ubiqueDevice.id,
            prescanDuration: const Duration(seconds: 1),
            withServices: []);

    currentConnectionStream.listen((event) async {
      if (kDebugMode) {
        print("Estado de la conexión: ${event.connectionState}");
      }
      switch (event.connectionState) {
        case DeviceConnectionState.connected:
          if (kDebugMode) {
            print("Dispositivo conectado exitosamente.");
          }
          setState(() {
            _foundDeviceWaitingToConnect = false;
            _connected = true;
          });
          await startSecurity();
          break;
        case DeviceConnectionState.disconnected:
          if (kDebugMode) {
            print("Conexión desconectada.");
          }
          setState(() {
            _connected = false;
          });
          break;
        default:
          if (kDebugMode) {
            print("Estado de la conexión desconocido.");
          }
          break;
      }
    });
  }

  Future<void> waitForSecurityResponse() async {
    print("Esperando respuesta del dispositivo...");
    try {
      // Suscribirse a la característica para escuchar las respuestas del dispositivo
      final stream = flutterReactiveBle.subscribeToCharacteristic(
        QualifiedCharacteristic(
          serviceId: Uuid.parse("49535343-FE7D-4AE5-8FA9-9FAFD205E455"),
          characteristicId: Uuid.parse("49535343-8841-43F4-A8D4-ECBE34729BB4"),
          deviceId: _ubiqueDevice.id,
        ),
      );

      // Escuchar las respuestas en el stream
      stream.listen(
        (response) {
          print("Respuesta recibida: $response");

          // Procesar la respuesta en función del primer byte
          if (response[0] == 2) {
            print("Dispositivo ya logado.");
            // Salimos si ya está logado
          } else if (response[0] == 1) {
            print("Respuesta correcta.");
            challenge = [0, 0, 0, 0]; // Resetear el reto
            return; // Salimos si la respuesta es correcta
          } else if (response[0] == 0) {
            print("Respuesta incorrecta, generando nuevo reto.");
            challenge = generateNewChallenge();
            sendChallenge(1); // Enviar nuevo desafío
          }
        },
        onError: (error) {
          print("Error al recibir respuesta: $error");
        },
        onDone: () {
          print("Stream de notificación cerrado.");
        },
      );
    } catch (e) {
      print("Error al esperar respuesta de seguridad: $e");
    }
  }

// Función para enviar el desafío al dispositivo (FUN_INIT)
  Future<void> sendChallenge(int P) async {
    List<int> data = [
      0,
      P,
      challenge[0],
      challenge[1],
      challenge[2],
      challenge[3]
    ];

    try {
      await flutterReactiveBle.writeCharacteristicWithResponse(
        QualifiedCharacteristic(
          serviceId: Uuid.parse("49535343-FE7D-4AE5-8FA9-9FAFD205E455"),
          characteristicId: Uuid.parse("49535343-8841-43F4-A8D4-ECBE34729BB4"),
          deviceId: _ubiqueDevice.id,
        ),
        value: data,
      );
      print("Desafío enviado al dispositivo.");
    } catch (e) {
      print("Error al enviar desafío: $e");
    }
  }

// Función para generar un nuevo reto
  List<int> generateNewChallenge() {
    return [
      Random().nextInt(256),
      Random().nextInt(256),
      Random().nextInt(256),
      Random().nextInt(256)
    ];
  }

// Función para iniciar la seguridad
  Future<void> startSecurity() async {
    print("Iniciando seguridad...");

    // Enviar el desafío al dispositivo
    await sendChallenge(0); // El 0 indica que es un nuevo reto

    // Llamar al siguiente paso: manejar la respuesta de seguridad
    await waitForSecurityResponse(); // Esperamos la respuesta real del dispositivo

    // Continuamos con la solicitud de la información del dispositivo
    await requestDeviceInfo();

    // Finalmente, manejamos la respuesta de la información del dispositivo
    await Future.delayed(const Duration(
        seconds: 2)); // Esperamos un momento antes de procesar la respuesta
    await handleDeviceInfoResponse([
      1,
      0x12,
      0x34,
      0x56,
      0x78,
      0x9A,
      0xBC,
      1,
      0,
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      0
    ]);
  }

// Función para obtener la información del dispositivo (FUN_INFO)
  Future<void> requestDeviceInfo() async {
    List<int> data = [2, 0]; // FUN_INFO = 2, con parámetro 00

    try {
      await flutterReactiveBle.writeCharacteristicWithResponse(
        QualifiedCharacteristic(
          serviceId: Uuid.parse("49535343-FE7D-4AE5-8FA9-9FAFD205E455"),
          characteristicId: Uuid.parse("49535343-8841-43F4-A8D4-ECBE34729BB4"),
          deviceId: _ubiqueDevice.id,
        ),
        value: data,
      );
      if (kDebugMode) {
        print("Información del dispositivo solicitada.");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error al solicitar información del dispositivo: $e");
      }
    }
  }

// Función para manejar la respuesta de la información del dispositivo (FUN_INFO_R)
  Future<void> handleDeviceInfoResponse(List<int> data) async {
    print(
        "Longitud de data: ${data.length}"); // Imprime la longitud de la lista data

    if (data[0] == 1) {
      String macAddress = data
          .sublist(1, 7)
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join(":");
      if (kDebugMode) {
        print("MAC Address: $macAddress");
      }

      int rate = data[7];
      if (kDebugMode) {
        print("Tarifa: $rate");
      }

      int powerType = data[8];
      if (kDebugMode) {
        print("Tipo de alimentación: ${powerType == 0 ? "Fuente" : "Batería"}");
      }

      int hwVersion = data[9];
      int swVersion = data[10];
      if (kDebugMode) {
        print("Versión HW: $hwVersion, Versión SW de comunicación: $swVersion");
      }

      // Comprobamos si la longitud de la lista permite acceder hasta el índice 18
      if (data.length >= 19) {
        // Si la lista es lo suficientemente larga, iteramos sobre los endpoints
        for (int i = 11; i <= 18; i += 2) {
          int hwType = data[i];
          int swVersionEndpoint = data[i + 1];
          if (kDebugMode) {
            print(
                "Endpoint ${i ~/ 2}: Tipo HW = $hwType, Versión SW = $swVersionEndpoint");
          }
        }
      } else {
        if (kDebugMode) {
          print(
              "Datos de endpoints no disponibles. La longitud de la lista es menor a 19.");
        }
      }
    }
  }
  Future<void> resetDevice() async {
    print("Iniciando proceso de reset...");

    // Enviar el comando de reset (como si fuera un desafío pero con la función de reset)
    await sendResetCommand();

    // Esperar la respuesta del dispositivo
    bool resetSuccess = await waitForResetResponse();

    if (resetSuccess) {
      // Solo intentar reconectar si el reset fue exitoso
      await _reconnect();
    } else {
      print("El proceso de reset falló, no se intentará reconectar.");
    }
  }

// Función para enviar el comando de reset (FUN_RESET)
  Future<void> sendResetCommand() async {
    // Crear el paquete de reset. Similar al desafío pero con los parámetros para resetear
    List<int> data = [0x26, 0xAA, 0x00]; // Comando de reset SW (FUN_RESET = 0x26, 0xAA para reset SW, 0x00 sin temporización)

    try {
      await flutterReactiveBle.writeCharacteristicWithResponse(
        QualifiedCharacteristic(
          serviceId: Uuid.parse("49535343-FE7D-4AE5-8FA9-9FAFD205E455"),
          characteristicId: Uuid.parse("49535343-8841-43F4-A8D4-ECBE34729BB4"),
          deviceId: _ubiqueDevice.id,
        ),
        value: data,
      );
      print("Comando de reset enviado.");
    } catch (e) {
      print("Error al enviar el comando de reset: $e");
    }
  }

  Future<bool> waitForResetResponse() async {
    print("Esperando respuesta del dispositivo para el reset...");

    bool resetCompleted = false;

    try {
      // Suscribirse a la característica para recibir notificaciones
      final stream = flutterReactiveBle.subscribeToCharacteristic(
        QualifiedCharacteristic(
          serviceId: Uuid.parse("49535343-FE7D-4AE5-8FA9-9FAFD205E455"),
          characteristicId: Uuid.parse("49535343-8841-43F4-A8D4-ECBE34729BB4"),
          deviceId: _ubiqueDevice.id,
        ),
      );

      // Escuchar las respuestas en el stream
      stream.listen(
            (response) {
          print("Respuesta recibida: $response");  // Debugging: log all responses

          // Verificar que la respuesta es correcta
          if (response.length > 1) {
            if (response[0] == 0x27 && response[1] == 0x01) {
              print("Reset completado correctamente.");
              resetCompleted = true;
            } else {
              print("Respuesta no esperada para el reset, pero procesada.");
            }
          } else {
            print("Respuesta incompleta o no válida.");
          }
        },
        onError: (error) {
          print("Error al recibir respuesta del reset: $error");
        },
        onDone: () {
          print("Stream de notificación cerrado.");
        },
      );

      // Asegúrate de que el flujo esté activo por el tiempo necesario
      await Future.delayed(Duration(seconds: 10));  // Increase delay if needed

    } catch (e) {
      print("Error al esperar la respuesta del reset: $e");
    }

    // Return true if reset was successful, false otherwise
    return resetCompleted;
  }






// Volver a realizar la conexión si es necesario
  Future<void> _reconnect() async {
    try {
      // Esto reintenta la conexión con el dispositivo, si se perdió la conexión después del reset
      final connection = await flutterReactiveBle.connectToDevice(
        id: _ubiqueDevice!.id,
        connectionTimeout: Duration(seconds: 5),
      );

      print("Conexión restablecida con el dispositivo: ${_ubiqueDevice!.id}");
    } catch (e) {
      print("Error al restablecer la conexión: $e");
    }
  }

  @override
  void dispose() {
    super.dispose();
    if (kDebugMode) {
      print("Destruyendo el objeto y cancelando el escaneo...");
    }
    _scanStream.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Escaneo BLE")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Indicador de estado durante el escaneo
            if (_scanStarted) const CircularProgressIndicator(),

            // Mostrar nombre y ID del dispositivo encontrado
            if (_scanFinished && !_connected)
              Column(
                children: [
                  const Text("Dispositivo encontrado:",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("ID: ${_ubiqueDevice.id}",
                      style: const TextStyle(fontSize: 16)),
                  Text("Nombre: ${_ubiqueDevice.name}",
                      style: const TextStyle(fontSize: 16)),
                ],
              ),

            // Si el dispositivo está conectado, mostrar el mensaje y detalles
            if (_connected)
              Column(
                children: [
                  const Text("Conectado exitosamente al dispositivo",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("ID: ${_ubiqueDevice.id}",
                      style: const TextStyle(fontSize: 16)),
                  Text("Nombre: ${_ubiqueDevice.name}",
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ElevatedButton(
              onPressed: () async {
                await resetDevice();
              },
              child: const Text('Resetear Dispositivo'),
            ),


          ],
        ),
      ),
    );
  }
}
