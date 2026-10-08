import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../data/audio/soloud_audition_engine.dart';
import '../data/audio/soloud_plugin_binding.dart';
import '../data/repositories/impl/engine_instrument_audition_repository.dart';
import '../data/repositories/impl/engine_playback_repository.dart';
import '../data/repositories/impl/file_arrangement_library_repository.dart';
import '../data/repositories/impl/file_instrument_library_repository.dart';
import '../data/repositories/impl/file_loop_library_repository.dart';
import '../data/repositories/impl/soloud_spike_repository.dart';
import '../data/services/instrument_file_store.dart';
import '../data/services/json_file_store.dart';
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
  Directory folder(String name) =>
      Directory('${documents.path}${Platform.pathSeparator}$name');
  final loops = FileLoopLibraryRepository(JsonFileStore(folder('loops')));
  final arrangements = FileArrangementLibraryRepository(
    JsonFileStore(folder('arrangements')),
  );
  await Future.wait([loops.load(), arrangements.load()]);
  return SynesterraApp(
    instrumentLibrary: library,
    loopLibrary: loops,
    arrangementLibrary: arrangements,
    audioSpikeRepositoryFactory: SoloudSpikeRepository.new,
    // The engine starts on the first audition, never at launch.
    instrumentAudition: EngineInstrumentAuditionRepository(
      SoloudAuditionEngine(),
    ),
    // Shared by the Loop and Arrangement panels; nothing starts before the
    // first Play.
    playback: EnginePlaybackRepository(
      engine: flutterSoloudPlaybackEngine(),
      instruments: library,
    ),
  );
}
