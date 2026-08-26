import 'package:flutter/material.dart';
import '../database/database_helper.dart';

class BirdProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _birds = [];

  List<Map<String, dynamic>> get birds => _birds;

  Future<void> loadBirds() async {
    _birds = await DatabaseHelper.instance.getBirds();
    notifyListeners();
  }

  Future<void> addBird(Map<String, dynamic> bird) async {
    await DatabaseHelper.instance.insertBird(bird);
    await loadBirds();
  }
}