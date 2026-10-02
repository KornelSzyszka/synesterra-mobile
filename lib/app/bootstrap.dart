import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../data/repositories/impl/file_instrument_library_repository.dart';
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
  return SynesterraApp(instrumentLibrary: library);
}
