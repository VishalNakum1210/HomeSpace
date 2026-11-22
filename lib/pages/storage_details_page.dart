import 'package:flutter/material.dart';
import '../domain/repositories.dart';
import '../widgets/storage_meter_card.dart';

class StorageDetailsPage extends StatelessWidget {
  final HomeRepository repository;
  const StorageDetailsPage({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage & Space'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: StorageMeterCard(repository: repository),
      ),
    );
  }
}
