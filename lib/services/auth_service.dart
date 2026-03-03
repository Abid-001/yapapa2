import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/preset_message.dart';
import 'group_listener_service.dart';
import 'screentime_service.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  UserModel? _currentUser;
  GroupModel? _currentGroup;
  bool _isLoading = true;
  String? _errorMessage;
  final GroupListenerService _listenerService = GroupListenerService();

  UserModel? get currentUser => _currentUser;
  GroupModel? get currentGroup => _currentGroup;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void initSession(String? savedUid, String? savedGroupId) async {
    if (savedUid == null || savedGroupId == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    try {
      // Sign in anonymously if no Firebase user
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }
      final userDoc = await _db.collection('users').doc(savedUid).get();
      if (userDoc.exists) {
        _currentUser = UserModel.fromMap(userDoc.data()!);
        final groupDoc =
            await _db.collection('groups').doc(savedGroupId).get();
        if (groupDoc.exists) {
          _currentGroup = GroupModel.fromMap(groupDoc.data()!);
          _listenerService.startListening(
            uid: _currentUser!.uid,
            groupId: _currentGroup!.groupId,
            username: _currentUser!.username,
          );
        }
      }
    } catch (_) {
      // Session restore failed, force re-login
      _currentUser = null;
      _currentGroup = null;
      await _clearSession();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<String?> createGroup({
    required String username,
    required String pin,
    String phoneNumber = '',
  }) async {
    _errorMessage = null;
    try {
      // Sign in anonymously
      final cred = await _auth.signInAnonymously();
      final uid = cred.user!.uid;

      // Generate a 6-char invite code
      final inviteCode = _generateCode();
      final groupId = _db.collection('groups').doc().id;

      final now = DateTime.now();

      final user = UserModel(
        uid: uid,
        username: username.trim(),
        groupId: groupId,
        isAdmin: true,
        joinedAt: now,
        phoneNumber: phoneNumber.trim(),
      );

      final group = GroupModel(
        groupId: groupId,
        inviteCode: inviteCode,
        adminUid: uid,
        memberUids: [uid],
        expenseTypes: ['Food', 'Transport', 'Shopping', 'Other'],
        createdAt: now,
      );

      // Store PIN as simple hash
      final pinHash = _hashPin(pin);

      // Batch write
      final batch = _db.batch();
      batch.set(_db.collection('users').doc(uid), user.toMap());
      batch.set(_db.collection('groups').doc(groupId), group.toMap());
      batch.set(_db.collection('pins').doc(uid), {'pin': pinHash});

      // Add default preset messages
      for (final preset in PresetMessage.defaults(groupId)) {
        batch.set(
          _db
              .collection('groups')
              .doc(groupId)
              .collection('presets')
              .doc(preset.id),
          preset.toMap(),
        );
      }

      await batch.commit();

      _currentUser = user;
      _currentGroup = group;
      await _saveSession(uid, groupId);
      _listenerService.startListening(
        uid: uid,
        groupId: groupId,
        username: user.username,
      );
      notifyListeners();
      return null; // No error
    } catch (e) {
      _errorMessage = 'Failed to create group. Please try again.';
      notifyListeners();
      return _errorMessage;
    }
  }

  Future<String?> joinGroup({
    required String username,
    required String pin,
    required String inviteCode,
    String phoneNumber = '',
  }) async {
    _errorMessage = null;
    try {
      // Sign in anonymously FIRST so Firestore rules (auth != null) allow reads
      final cred = await _auth.signInAnonymously();
      final uid = cred.user!.uid;

      // Find group by invite code
      final query = await _db
          .collection('groups')
          .where('inviteCode', isEqualTo: inviteCode.trim().toUpperCase())
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        await _auth.signOut();
        _errorMessage = 'Invalid invite code. Please check and try again.';
        notifyListeners();
        return _errorMessage;
      }

      final groupData = query.docs.first.data() as Map<String, dynamic>;
      final group = GroupModel.fromMap(groupData);

      if (group.memberUids.length >= 20) {
        await _auth.signOut();
        _errorMessage = 'This group is full (max 20 members).';
        notifyListeners();
        return _errorMessage;
      }

      // Check username uniqueness in group
      final existingUsers = await _db
          .collection('users')
          .where('groupId', isEqualTo: group.groupId)
          .where('username', isEqualTo: username.trim())
          .get();

      if (existingUsers.docs.isNotEmpty) {
        await _auth.signOut();
        _errorMessage = 'This username is already taken in this group.';
        notifyListeners();
        return _errorMessage;
      }
      final now = DateTime.now();

      // Check if the solo admin left and we should make this new joiner admin
      final awaitingTransfer = groupData['awaitingAdminTransfer'] == true;
      final originalAdminUid = groupData['originalAdminUid'] as String?;
      final becomeAdmin = awaitingTransfer;

      final user = UserModel(
        uid: uid,
        username: username.trim(),
        groupId: group.groupId,
        isAdmin: becomeAdmin,
        joinedAt: now,
        phoneNumber: phoneNumber.trim(),
      );

      final pinHash = _hashPin(pin);

      final batch = _db.batch();
      batch.set(_db.collection('users').doc(uid), user.toMap());
      batch.set(_db.collection('pins').doc(uid), {'pin': pinHash});
      final groupUpdate = <String, dynamic>{
        'memberUids': FieldValue.arrayUnion([uid]),
      };
      if (becomeAdmin) {
        // Transfer admin to new joiner; demote original admin
        groupUpdate['adminUid'] = uid;
        groupUpdate['awaitingAdminTransfer'] = FieldValue.delete();
        groupUpdate['originalAdminUid'] = FieldValue.delete();
        if (originalAdminUid != null) {
          batch.update(_db.collection('users').doc(originalAdminUid), {'isAdmin': false});
        }
      }
      batch.update(_db.collection('groups').doc(group.groupId), groupUpdate);

      await batch.commit();

      final updatedGroup = group.copyWith(
        memberUids: [...group.memberUids, uid],
        adminUid: becomeAdmin ? uid : group.adminUid,
      );

      _currentUser = user;
      _currentGroup = updatedGroup;
      await _saveSession(uid, group.groupId);
      _listenerService.startListening(
        uid: uid,
        groupId: group.groupId,
        username: user.username,
      );
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Failed to join group. Please try again.';
      notifyListeners();
      return _errorMessage;
    }
  }

  Future<String?> loginWithPin({
    required String username,
    required String pin,
    required String inviteCode,
  }) async {
    _errorMessage = null;
    try {
      // Step 1: Find group by invite code (unambiguous identifier)
      final inviteUpper = inviteCode.trim().toUpperCase();
      if (inviteUpper.isEmpty) {
        _errorMessage = 'Please enter your group invite code.';
        notifyListeners();
        return _errorMessage;
      }
      final groupQuery = await _db
          .collection('groups')
          .where('inviteCode', isEqualTo: inviteUpper)
          .limit(1)
          .get();
      if (groupQuery.docs.isEmpty) {
        _errorMessage = 'Group not found. Check your invite code.';
        notifyListeners();
        return _errorMessage;
      }
      final group = GroupModel.fromMap(groupQuery.docs.first.data() as Map<String, dynamic>);

      // Step 2: Find user by username within that group
      final userQuery = await _db
          .collection('users')
          .where('username', isEqualTo: username.trim())
          .where('groupId', isEqualTo: group.groupId)
          .limit(1)
          .get();
      if (userQuery.docs.isEmpty) {
        _errorMessage = 'Username not found in this group. Check your username and invite code.';
        notifyListeners();
        return _errorMessage;
      }
      final user = UserModel.fromMap(userQuery.docs.first.data() as Map<String, dynamic>);

      // Step 3: Verify PIN
      final pinDoc = await _db.collection('pins').doc(user.uid).get();
      final pinData = pinDoc.data() as Map<String, dynamic>?;
      if (!pinDoc.exists || pinData == null || pinData['pin'] != _hashPin(pin)) {
        _errorMessage = 'Incorrect PIN.';
        notifyListeners();
        return _errorMessage;
      }

      // Step 4: Authenticate
      await _auth.signInAnonymously();
      _currentUser = user;
      _currentGroup = group;
      await _saveSession(user.uid, group.groupId);
      _listenerService.startListening(
        uid: user.uid,
        groupId: group.groupId,
        username: user.username,
      );
      notifyListeners();
      // Backfill historical screentime in background (non-blocking)
      // This recovers data from Android UsageStats for days missed while logged out
      ScreentimeService().backfillHistoricalScreentime(
        uid: user.uid,
        groupId: group.groupId,
      ).ignore();
      return null;
    } catch (e) {
      _errorMessage = 'Login failed. Please try again.';
      notifyListeners();
      return _errorMessage;
    }
  }

  Future<String?> removeMember(String targetUid) async {
    if (_currentUser == null || _currentGroup == null) return 'Not logged in';
    if (!_currentUser!.isAdmin) return 'Only admin can remove members';
    if (targetUid == _currentUser!.uid) return 'You cannot remove yourself';
    try {
      final batch = _db.batch();
      batch.update(_db.collection('groups').doc(_currentGroup!.groupId), {
        'memberUids': FieldValue.arrayRemove([targetUid]),
      });
      batch.delete(_db.collection('users').doc(targetUid));
      batch.delete(_db.collection('pins').doc(targetUid));
      await batch.commit();
      final updatedUids = _currentGroup!.memberUids
          .where((id) => id != targetUid)
          .toList();
      _currentGroup = _currentGroup!.copyWith(memberUids: updatedUids);
      notifyListeners();
      return null;
    } catch (e) {
      return 'Failed to remove member. Try again.';
    }
  }

  Future<void> transferAdmin(String newAdminUid) async {
    if (_currentUser == null || _currentGroup == null) return;
    try {
      final batch = _db.batch();
      batch.update(_db.collection('groups').doc(_currentGroup!.groupId), {
        'adminUid': newAdminUid,
      });
      batch.update(_db.collection('users').doc(_currentUser!.uid), {
        'isAdmin': false,
      });
      batch.update(_db.collection('users').doc(newAdminUid), {
        'isAdmin': true,
      });
      await batch.commit();

      _currentUser = _currentUser!.copyWith(isAdmin: false);
      _currentGroup = _currentGroup!.copyWith(adminUid: newAdminUid);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateDefaultScreentime(int minutes) async {
    if (_currentGroup == null) return;
    try {
      await _db.collection('groups').doc(_currentGroup!.groupId).update({
        'defaultScreentimeMinutes': minutes,
      });
      _currentGroup = _currentGroup!.copyWith(defaultScreentimeMinutes: minutes);
      notifyListeners();
    } catch (_) {}
  }

  
  Future<void> updateMonthlyReminders(List<MonthlyReminder> reminders) async {
    if (_currentGroup == null) return;
    await _db.collection('groups').doc(_currentGroup!.groupId).update({
      'monthlyReminders': reminders.map((r) => r.toMap()).toList(),
    });
    _currentGroup = _currentGroup!.copyWith(monthlyReminders: reminders);
    notifyListeners();
  }

  Future<void> updateExpenseTypes(List<String> types) async {
    if (_currentGroup == null) return;
    try {
      await _db.collection('groups').doc(_currentGroup!.groupId).update({
        'expenseTypes': types,
      });
      _currentGroup = _currentGroup!.copyWith(expenseTypes: types);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshGroup() async {
    if (_currentGroup == null) return;
    try {
      final doc =
          await _db.collection('groups').doc(_currentGroup!.groupId).get();
      if (doc.exists) {
        _currentGroup = GroupModel.fromMap(doc.data()!);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    _listenerService.stopListening();
    // If solo admin logs out, flag the group so next joiner becomes admin
    try {
      final user = _currentUser;
      final group = _currentGroup;
      if (user != null && group != null && user.isAdmin && group.memberUids.length == 1) {
        await _db.collection('groups').doc(group.groupId).update({
          'awaitingAdminTransfer': true,
          'originalAdminUid': user.uid,
        });
      }
    } catch (_) {}
    await _clearSession();
    await _auth.signOut();
    _currentUser = null;
    _currentGroup = null;
    notifyListeners();
  }

  Future<void> _saveSession(String uid, String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_uid', uid);
    await prefs.setString('session_group_id', groupId);
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_uid');
    await prefs.remove('session_group_id');
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = DateTime.now().millisecondsSinceEpoch;
    return List.generate(
        6, (i) => chars[(rand ~/ (i + 1)) % chars.length]).join();
  }

  String _hashPin(String pin) {
    // Simple deterministic hash - not crypto-secure but fine for this use case
    int hash = 5381;
    for (final c in pin.codeUnits) {
      hash = ((hash << 5) + hash) + c;
    }
    return hash.toRadixString(16);
  }
}
