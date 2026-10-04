import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/repositories/audio_spike_repository.dart';

/// Measurement controls only. The repository owns transport and the audio path.
final class AudioSpikeView extends StatefulWidget {
  const AudioSpikeView({super.key, required this.repository});

  final AudioSpikeRepository repository;

  @override
  State<AudioSpikeView> createState() => _AudioSpikeViewState();
}

final class _AudioSpikeViewState extends State<AudioSpikeView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _stress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _stressEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.repository.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stress.dispose();
    unawaited(widget.repository.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioSpikeStatus>(
      valueListenable: widget.repository.status,
      builder: (context, status, _) => Scaffold(
        appBar: AppBar(title: const Text('AUD-043 audio spike')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Transport: ${status.transport.name}',
              key: const Key('spike-transport'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('spike-start'),
                  onPressed:
                      status.busy || status.transport == SpikeTransport.playing
                      ? null
                      : () => unawaited(widget.repository.start()),
                  child: const Text('Start'),
                ),
                OutlinedButton(
                  key: const Key('spike-pause'),
                  onPressed: status.transport == SpikeTransport.playing
                      ? () => unawaited(widget.repository.pause())
                      : null,
                  child: const Text('Pause'),
                ),
                OutlinedButton(
                  key: const Key('spike-stop'),
                  onPressed: status.transport == SpikeTransport.stopped
                      ? null
                      : () => unawaited(widget.repository.stop()),
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Tempo: ${status.bpm} BPM'),
            Slider(
              key: const Key('spike-tempo'),
              value: status.bpm.toDouble(),
              min: 20,
              max: 300,
              divisions: 280,
              label: '${status.bpm} BPM',
              onChanged: (value) => widget.repository.setTempo(value.round()),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '3:2', label: Text('3:2')),
                ButtonSegment(value: '5:4', label: Text('5:4')),
              ],
              selected: {status.scene},
              onSelectionChanged: (selected) =>
                  widget.repository.setScene(selected.first),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2 layers')),
                ButtonSegment(value: 4, label: Text('4 layers')),
              ],
              selected: {status.layers},
              onSelectionChanged: (selected) =>
                  widget.repository.setLayers(selected.first),
            ),
            SwitchListTile(
              title: const Text('Drone'),
              value: status.drone,
              onChanged: widget.repository.setDrone,
            ),
            SwitchListTile(
              title: const Text('UI stress'),
              subtitle: const Text('Animates a dense canvas during playback'),
              value: _stressEnabled,
              onChanged: (enabled) {
                setState(() => _stressEnabled = enabled);
                widget.repository.setStress(enabled);
                if (enabled) {
                  _stress.repeat();
                } else {
                  _stress.stop();
                }
              },
            ),
            if (_stressEnabled)
              SizedBox(
                height: 120,
                child: AnimatedBuilder(
                  animation: _stress,
                  builder: (_, _) =>
                      CustomPaint(painter: _StressPainter(_stress.value)),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: const Key('spike-ci'),
              onPressed:
                  status.transport == SpikeTransport.playing && !status.busy
                  ? () => unawaited(widget.repository.runInstrumentCheck())
                  : null,
              child: const Text('Run C-I instrument buffers'),
            ),
            FilledButton.tonal(
              key: const Key('spike-export'),
              onPressed: () async {
                try {
                  final path = await widget.repository.exportDiagnostics();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Saved diagnostics: $path')),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export failed: $error')),
                    );
                  }
                }
              },
              child: const Text('Export diagnostics'),
            ),
            if (status.busy) const LinearProgressIndicator(),
            if (status.error != null) Text('Audio error: ${status.error}'),
            Text(
              'Voices: ${status.activeVoices} active / ${status.totalVoices} total / ${status.maxVoices} limit · Buffers: ${status.loadedBuffers}',
            ),
            Text('Late: ${status.late} · Rejected: ${status.rejected}'),
            if (status.exportPath != null) SelectableText(status.exportPath!),
            const SizedBox(height: 8),
            const Text(
              'The log records engine enqueue and scheduler wake-up. Physical recording is required for onset, route latency, xruns and sound quality.',
            ),
          ],
        ),
      ),
    );
  }
}

final class _StressPainter extends CustomPainter {
  _StressPainter(this.phase);
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 240; i++) {
      final angle = i * 0.618 + phase * math.pi * 2;
      final radius = 2.0 + i * 0.2;
      final center = Offset(
        size.width / 2 + math.cos(angle) * radius,
        size.height / 2 + math.sin(angle) * radius,
      );
      canvas.drawCircle(
        center,
        3 + (i % 7).toDouble(),
        Paint()
          ..color = Color.fromARGB(110, (i * 29) % 255, 120, (i * 13) % 255),
      );
    }
  }

  @override
  bool shouldRepaint(_StressPainter oldDelegate) => phase != oldDelegate.phase;
}
