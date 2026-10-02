import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../data/audio/soloud_audition_engine.dart';
import '../data/repositories/impl/engine_instrument_audition_repository.dart';
import '../data/repositories/impl/file_instrument_library_repository.dart';
import '../data/repositories/impl/soloud_spike_repository.dart';
import '../data/services/instrument_file_store.dart';
import 'synesterra_app.dart';

/// Resolves platform paths and builds the app with its real repositories.
Future<Widget> createApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final library = FileInstrumentLibraryRepository(
    InstrumentFileStore(
      Directory('${documents.path}${Platform.pathSeparator}instruments'),
    ),
  );
  await library.load();
  return SynesterraApp(
    instrumentLibrary: library,
    audioSpikeRepositoryFactory: SoloudSpikeRepository.new,
    // The engine starts on the first audition, never at launch.
    instrumentAudition: EngineInstrumentAuditionRepository(
      SoloudAuditionEngine(),
    ),
  );
}
