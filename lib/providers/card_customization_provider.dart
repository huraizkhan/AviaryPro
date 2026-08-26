import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CardCustomizationProvider extends ChangeNotifier {
  static const Map<String, List<String>> _defaults = {
    'dashboard': ['birds', 'eggs', 'pairs', 'chicks'],
    'birds': ['summary', 'automaticCount'],
    'breeding': ['allPairs', 'activePairs', 'eggs', 'chicks'],
    'finance': ['month', 'year', 'feed'],
  };

  static const List<String> birdFieldIds = [
    'cage',
    'species',
    'mutation',
    'age',
    'pair',
    'saleStatus',
    'gender',
    'eyeColor',
    'downColor',
    'mate',
    'parents',
    'parentCages',
    'source',
    'hatchDate',
    'sourceDate',
    'nest',
    'notes',
  ];

  static const Map<String, String> _defaultBirdStyles = {
    'cage': 'pill',
    'species': 'pill',
    'mutation': 'pill',
    'age': 'pill',
    'pair': 'pill',
    'saleStatus': 'hidden',
    'gender': 'hidden',
    'eyeColor': 'hidden',
    'downColor': 'hidden',
    'mate': 'hidden',
    'parents': 'hidden',
    'parentCages': 'hidden',
    'source': 'hidden',
    'hatchDate': 'hidden',
    'sourceDate': 'hidden',
    'nest': 'hidden',
    'notes': 'hidden',
  };

  final Map<String, List<String>> _orders = {};
  final Map<String, Set<String>> _hidden = {};
  List<String> _birdFieldOrder = List<String>.from(birdFieldIds);
  final Map<String, String> _birdFieldStyles = {..._defaultBirdStyles};
  bool loaded = false;

  List<String> orderFor(String screen) =>
      List.unmodifiable(_orders[screen] ?? _defaults[screen] ?? const []);

  bool isVisible(String screen, String id) =>
      !(_hidden[screen]?.contains(id) ?? false);

  List<String> get birdFieldOrder => List.unmodifiable(_birdFieldOrder);

  String birdFieldStyle(String id) => _birdFieldStyles[id] ?? 'hidden';

  bool birdFieldVisible(String id) => birdFieldStyle(id) != 'hidden';

  Set<String> get birdFields => _birdFieldOrder
      .where((id) => birdFieldVisible(id))
      .toSet();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _defaults.entries) {
      final savedOrder = prefs.getStringList('card_order_${entry.key}');
      final known = entry.value.toSet();
      final order = <String>[];
      if (savedOrder != null) order.addAll(savedOrder.where(known.contains));
      order.addAll(entry.value.where((id) => !order.contains(id)));
      _orders[entry.key] = order;
      _hidden[entry.key] =
          (prefs.getStringList('card_hidden_${entry.key}') ?? const <String>[])
              .where(known.contains)
              .toSet();
    }

    final savedOrder = prefs.getStringList('bird_card_field_order');
    if (savedOrder != null) {
      final known = birdFieldIds.toSet();
      _birdFieldOrder = savedOrder.where(known.contains).toList();
      _birdFieldOrder.addAll(
        birdFieldIds.where((id) => !_birdFieldOrder.contains(id)),
      );
    }

    for (final id in birdFieldIds) {
      final savedStyle = prefs.getString('bird_card_style_$id');
      if (const {'pill', 'text', 'icon', 'hidden'}.contains(savedStyle)) {
        _birdFieldStyles[id] = savedStyle!;
      }
    }

    // Migrate the first experimental show/hide preference if it exists.
    final oldFields = prefs.getStringList('bird_card_fields');
    if (oldFields != null &&
        !birdFieldIds.any((id) => prefs.containsKey('bird_card_style_$id'))) {
      for (final id in birdFieldIds) {
        _birdFieldStyles[id] = oldFields.contains(id)
            ? (_defaultBirdStyles[id] == 'hidden' ? 'pill' : _defaultBirdStyles[id]!)
            : 'hidden';
      }
    }

    loaded = true;
    notifyListeners();
  }

  Future<void> reorder(String screen, int oldIndex, int newIndex) async {
    final list = _orders.putIfAbsent(
      screen,
      () => List<String>.from(_defaults[screen] ?? const <String>[]),
    );
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

  Future<void> reorderBirdField(int oldIndex, int newIndex) async {
    final item = _birdFieldOrder.removeAt(oldIndex);
    _birdFieldOrder.insert(newIndex, item);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bird_card_field_order', _birdFieldOrder);
    notifyListeners();
  }

  Future<void> setBirdFieldStyle(String id, String style) async {
    if (!birdFieldIds.contains(id) ||
        !const {'pill', 'text', 'icon', 'hidden'}.contains(style)) {
      return;
    }
    _birdFieldStyles[id] = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bird_card_style_$id', style);
    notifyListeners();
  }

  Future<void> setBirdFieldVisible(String id, bool visible) async {
    await setBirdFieldStyle(
      id,
      visible ? (_defaultBirdStyles[id] == 'hidden' ? 'pill' : _defaultBirdStyles[id]!) : 'hidden',
    );
  }

  Future<void> resetScreen(String screen) async {
    _orders[screen] = List<String>.from(_defaults[screen] ?? const <String>[]);
    _hidden[screen] = <String>{};
    await _saveScreen(screen);
    notifyListeners();
  }

  Future<void> resetBirdFields() async {
    _birdFieldOrder = List<String>.from(birdFieldIds);
    _birdFieldStyles
      ..clear()
      ..addAll(_defaultBirdStyles);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bird_card_field_order', _birdFieldOrder);
    for (final id in birdFieldIds) {
      await prefs.setString('bird_card_style_$id', _birdFieldStyles[id]!);
    }
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
