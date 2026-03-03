import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService extends ChangeNotifier {
  bool _isOffline = false;
  StreamSubscription? _sub;

  bool get isOffline => _isOffline;

  ConnectivityService() {
    _init();
  }

  Future<void> _init() async {
    // Check immediately
    final result = await Connectivity().checkConnectivity();
    _setOffline(_isNoConnection(result));

    // Listen for changes
    _sub = Connectivity().onConnectivityChanged.listen((result) {
      _setOffline(_isNoConnection(result));
    });
  }

  bool _isNoConnection(List<ConnectivityResult> results) {
    return results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
  }

  void _setOffline(bool value) {
    if (_isOffline != value) {
      _isOffline = value;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
