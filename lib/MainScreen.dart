import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import "./consts.dart";

class MainScreen extends StatefulWidget {
  static const routeName = '/main';
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  IOWebSocketChannel? mainChannel;
  IOWebSocketChannel? backupChannel;
  Socket? mainSocket;
  Socket? backupSocket;
  bool isConnected = false;
  bool isBackup = false;
  var clientID = const Uuid().v1();
  var mainDiff = 0.0;
  static const messageToBeEmitted = "15";

  void connectToMainServer() async {
    try {
      // Connect to the main server
      mainChannel = IOWebSocketChannel.connect('ws://$mainServer:8000/ws/$clientID');
      print('Successfully connected to main server!');
      isConnected = true;
      // Listen for the incoming messages from the server
      mainChannel!.stream.listen((message) async {
        // This means the execution was completed successfully
        if (!(message as String).contains('Latest') && !message.contains('{')) {
          print('Execution completed in $message seconds');
          return;
        }
        // If message is a JSON formatted String, parse it
        if ((message as String).contains('{')) {
          var message_obj = jsonDecode(message);
          // If message is replication, it means server unavailability is being simulated intentionally
          if (message_obj['message'] == 'replication') {
            mainDiff = message_obj['diff'];
            print('Main server not available. Time spent so far: $mainDiff');
            print("Connecting to backup server...");
            // Close the connection with main server and then connect to the backup server. Emit same message to backup server.
            mainChannel!.sink.close();
            connectToBackupServer();
            await Future.delayed(const Duration(seconds: 1));
            emitMessage(messageToBeEmitted);

          }
        } else {
          print('Received: $message');
          // Echo back the received message to the server
          mainChannel!.sink.add(message);
        }
      });
    } catch (e) {
      print(e.toString());
    }
  }

  void connectToBackupServer() {
    try {
      // Connect to the backup server
      backupChannel = IOWebSocketChannel.connect('ws://$backupServer:8000/ws/$clientID');
      isConnected = true;
      isBackup = true;
      print('Successfully connected to backup server!');
      // Listen for the incoming messages from the backup server
      backupChannel!.stream.listen((message) {
        // If message contains 'completed', print the execution time
        if (!(message as String).contains('Latest')) {
          print(message);
          var diff = double.parse(message);
          var replication_time = diff + mainDiff;
          print('Execution completed in ${isCombined ? diff : replication_time} seconds');
        } else {
          print('Received: $message');
        }
        // Echo back the received message to the server
        backupChannel!.sink.add(message);
      });
    } catch (e) {
      print("An error occurred: ${e.toString()}");
    }
  }

  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();

    connectToMainServer();

    initConnectivity();

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> initConnectivity() async {
    late ConnectivityResult result;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      result = await _connectivity.checkConnectivity();
    } on PlatformException catch (e) {
      print('An error occurred: ${e.toString()}');
      return;
    }

    if (!mounted) {
      return Future.value(null);
    }

    return _updateConnectionStatus(result);
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    // Update the visible connection status at screen
    setState(() {
      _connectionStatus = result;
    });
    if (result.name == 'none') {
      isConnected = false;
    } else {
      // This condition can only occur when phone regains network connection
      if (!isConnected) {
        connectToMainServer();
        emitMessage(messageToBeEmitted);
      }
    }
  }

  void emitMessage(String number) {
    // Check if connected
    if (isConnected) {
      // Send the number to the relevant server
      !isBackup ? mainChannel!.sink.add(number) : backupChannel!.sink.add(number);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Connectivity status: ${_connectionStatus.toString()}'),
            ElevatedButton(
              child: const Text('Start simulation'),
              onPressed: () {
                emitMessage(messageToBeEmitted);
              },
            ),
            ElevatedButton(
              child: const Text('Connect'),
              onPressed: () {
                // Connect to the relevant server (main or backup)
                !isBackup ? connectToMainServer() : connectToBackupServer();
              },
            ),
          ],
        ),
      ),
    );
  }
}
