import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Simple connectivity checker using Firestore's network status.
/// Notifies listeners when online/offline state changes.
class ConnectivityService extends ChangeNotifier {
  bool _isOffline = false;
  Timer? _timer;

  bool get isOffline => _isOffline;

  ConnectivityService() {
    _startChecking();
  }

  void _startChecking() {
    // Check every 15 seconds
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
    _check(); // immediate check
  }

  Future<void> _check() async {
    try {
      // A lightweight read to check connectivity
      await FirebaseFirestore.instance
          .collection('_ping')
          .doc('ping')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
      _setOffline(false);
    } catch (_) {
      _setOffline(true);
    }
  }

  void _setOffline(bool value) {
    if (_isOffline != value) {
      _isOffline = value;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
