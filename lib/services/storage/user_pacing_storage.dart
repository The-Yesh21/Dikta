import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/pacing/pacing_engine.dart';

/// Stored pacing calibration and settings profile for a user.
class UserPacingProfile {
  const UserPacingProfile({
    required this.userId,
    this.ageGroup,
    this.calibratedLpm = const {},
    this.lastUpdated,
  });

  final String userId;

  /// Selected age bracket: e.g. '8-10', '11-13', '14-17', '18+'
  final String? ageGroup;

  /// Calibrated Letters Per Minute (LPM) keyed by script family.
  final Map<ScriptType, double> calibratedLpm;

  final DateTime? lastUpdated;

  UserPacingProfile copyWith({
    String? userId,
    String? ageGroup,
    Map<ScriptType, double>? calibratedLpm,
    DateTime? lastUpdated,
  }) {
    return UserPacingProfile(
      userId: userId ?? this.userId,
      ageGroup: ageGroup ?? this.ageGroup,
      calibratedLpm: calibratedLpm ?? this.calibratedLpm,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'ageGroup': ageGroup,
      'calibratedLpm': calibratedLpm.map((k, v) => MapEntry(k.name, v)),
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  factory UserPacingProfile.fromJson(Map<String, dynamic> json) {
    final rawLpm = json['calibratedLpm'] as Map<String, dynamic>? ?? {};
    final lpmMap = <ScriptType, double>{};
    for (final entry in rawLpm.entries) {
      try {
        final script = ScriptType.values.firstWhere((s) => s.name == entry.key);
        final val = (entry.value as num).toDouble();
        lpmMap[script] = val;
      } catch (_) {}
    }

    return UserPacingProfile(
      userId: json['userId'] as String? ?? 'default_user',
      ageGroup: json['ageGroup'] as String?,
      calibratedLpm: lpmMap,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.tryParse(json['lastUpdated'] as String)
          : null,
    );
  }
}

/// Local JSON file storage service for persisting user calibration and pacing profiles.
class UserPacingStorageService {
  UserPacingStorageService({
    File? storageFile,
    bool inMemory = false,
  })  : _customFile = storageFile,
        _inMemory = inMemory,
        _inMemoryStore = inMemory ? <String, UserPacingProfile>{} : null;

  static const String defaultFileName = 'user_pacing_profiles.json';
  static const String defaultUserId = 'default_user';

  final File? _customFile;
  final bool _inMemory;
  final Map<String, UserPacingProfile>? _inMemoryStore;

  Future<File> _resolveFile() async {
    if (_customFile != null) {
      return _customFile;
    }
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$defaultFileName');
  }

  /// Loads all stored profiles keyed by userId.
  Future<Map<String, UserPacingProfile>> _loadAllProfiles() async {
    if (_inMemory && _inMemoryStore != null) {
      return Map<String, UserPacingProfile>.from(_inMemoryStore);
    }
    try {
      final file = await _resolveFile();
      if (!await file.exists()) {
        return {};
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return {};
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final results = <String, UserPacingProfile>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map<String, dynamic>) {
          results[entry.key] = UserPacingProfile.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }
      return results;
    } catch (_) {
      // In case of any I/O or decode error, return empty map safely
      return {};
    }
  }

  /// Saves the full map of profiles to local disk.
  Future<void> _saveAllProfiles(Map<String, UserPacingProfile> profiles) async {
    if (_inMemory && _inMemoryStore != null) {
      _inMemoryStore.clear();
      _inMemoryStore.addAll(profiles);
      return;
    }
    try {
      final file = await _resolveFile();
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      final encoded = jsonEncode(
        profiles.map((k, v) => MapEntry(k, v.toJson())),
      );
      await file.writeAsString(encoded, flush: true);
    } catch (_) {
      // Fail gracefully
    }
  }

  /// Retrieves the profile for [userId].
  Future<UserPacingProfile?> getProfile({String userId = defaultUserId}) async {
    final profiles = await _loadAllProfiles();
    return profiles[userId];
  }

  /// Saves or updates the profile for [profile.userId].
  Future<void> saveProfile(UserPacingProfile profile) async {
    final profiles = await _loadAllProfiles();
    profiles[profile.userId] = profile.copyWith(lastUpdated: DateTime.now());
    await _saveAllProfiles(profiles);
  }

  /// Persists calibrated LPM for a specific script and user.
  Future<void> saveCalibratedLpm({
    String userId = defaultUserId,
    required ScriptType script,
    required double lpm,
  }) async {
    final profiles = await _loadAllProfiles();
    final current = profiles[userId] ?? UserPacingProfile(userId: userId);
    final updatedLpm = Map<ScriptType, double>.from(current.calibratedLpm);
    updatedLpm[script] = lpm;

    profiles[userId] = current.copyWith(
      calibratedLpm: updatedLpm,
      lastUpdated: DateTime.now(),
    );
    await _saveAllProfiles(profiles);
  }

  /// Returns the saved calibrated LPM for a given script and user, or null if none saved.
  Future<double?> getCalibratedLpm({
    String userId = defaultUserId,
    required ScriptType script,
  }) async {
    final profile = await getProfile(userId: userId);
    return profile?.calibratedLpm[script];
  }

  /// Saves the user's selected age group.
  Future<void> saveAgeGroup({
    String userId = defaultUserId,
    required String ageGroup,
  }) async {
    final profiles = await _loadAllProfiles();
    final current = profiles[userId] ?? UserPacingProfile(userId: userId);
    profiles[userId] = current.copyWith(
      ageGroup: ageGroup,
      lastUpdated: DateTime.now(),
    );
    await _saveAllProfiles(profiles);
  }
}
