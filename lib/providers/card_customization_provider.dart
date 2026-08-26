import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CardCustomizationProvider extends ChangeNotifier {
  static const Map<String, List<String>> _defaults = {
    'dashboard': ['birds', 'eggs', 'pairs', 'chicks'],
    'birds': ['summary', 'automaticCount'],
    'breeding': ['allPairs', 'activePairs', 'eggs', 'chicks'],
    'finance': ['month', 'year', 'feed'],
  };

  static const List<String> _defaultBirdFields = [
    'species',
    'mutation',
    'age',
    'cage',
    'pair',
    'eyeColor',
  ];

  final Map<String, List<String>> _orders = {};
  final Map<String, Set<String>> _hidden = {};
  Set<String> _birdFields = {..._defaultBirdFields};
  bool loaded = false;

  List<String> orderFor(String screen) =>
      List.unmodifiable(_orders[screen] ?? _defaults[screen] ?? const []);

  bool isVisible(String screen, String id) => !(_hidden[screen]?.contains(id) ?? false);

  bool birdFieldVisible(String id) => _birdFields.contains(id);

  Set<String> get birdFields => Set.unmodifiable(_birdFields);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _defaults.entries) {
      final savedOrder = prefs.getStringList('card_order_${entry.key}');
      final known = entry.value.toSet();
      final order = <String>[];
      if (savedOrder != null) {
        order.addAll(savedOrder.where(known.contains));
      }
      order.addAll(entry.value.where((id) => !order.contains(id)));
      _orders[entry.key] = order;
      _hidden[entry.key] =
          (prefs.getStringList('card_hidden_${entry.key}') ?? const <String>[])
              .where(known.contains)
              .toSet();
    }
    final savedFields = prefs.getStringList('bird_card_fields');
    if (savedFields != null) {
      final knownFields = _defaultBirdFields.toSet();
      _birdFields = savedFields.where(knownFields.contains).toSet();
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> reorder(String screen, int oldIndex, int newIndex) async {
    final list = _orders.putIfAbsent(
      screen,
      () => List<String>.from(_defaults[screen] ?? const <String>[]),
    );
    if (newIndex > oldIndex) newIndex--;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await _saveScreen(screen);
    notifyListeners();
  }

  Future<void> setVisible(String screen, String id, bool visible) async {
    final hidden = _hidden.putIfAbsent(screen, () => <String>{});
    if (visible) {
      hidden.remove(id);
    } else {
      hidden.add(id);
    }
    await _saveScreen(screen);
    notifyListeners();
  }

  Future<void> setBirdFieldVisible(String id, bool visible) async {
    if (visible) {
      _birdFields.add(id);
    } else {
      _birdFields.remove(id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bird_card_fields', _birdFields.toList());
    notifyListeners();
  }

  Future<void> resetScreen(String screen) async {
    _orders[screen] = List<String>.from(_defaults[screen] ?? const <String>[]);
    _hidden[screen] = <String>{};
    await _saveScreen(screen);
    notifyListeners();
  }

  Future<void> resetBirdFields() async {
    _birdFields = {..._defaultBirdFields};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bird_card_fields', _birdFields.toList());
    notifyListeners();
  }

  Future<void> _saveScreen(String screen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('card_order_$screen', _orders[screen] ?? const []);
    await prefs.setStringList(
      'card_hidden_$screen',
      (_hidden[screen] ?? const <String>{}).toList(),
    );
  }
}
