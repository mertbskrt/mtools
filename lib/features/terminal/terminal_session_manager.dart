import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

class ActiveTerminalSession {
  final SSHClient client;
  final SSHSession session;
  final Terminal terminal;
  final TerminalController controller;
  final ValueNotifier<bool> connected;

  ActiveTerminalSession({
    required this.client,
    required this.session,
    required this.terminal,
    required this.controller,
    bool connected = true,
  }) : connected = ValueNotifier(connected);

  void close() {
    session.close();
    client.close();
  }
}

class TerminalSessionManager {
  TerminalSessionManager._();
  static final instance = TerminalSessionManager._();

  final Map<String, ActiveTerminalSession> _sessions = {};

  String keyFor(String host, int port, String username) =>
      '$username@$host:$port';

  ActiveTerminalSession? get(String key) => _sessions[key];

  void put(String key, ActiveTerminalSession session) {
    _sessions[key] = session;
  }

  void terminate(String key) {
    _sessions.remove(key)?.close();
  }

  void remove(String key) {
    _sessions.remove(key);
  }
}
