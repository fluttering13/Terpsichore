import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/ab_analysis/analysis_project.dart';
import '../../core/ab_analysis/pose_3d.dart';
import 'pose_3d_analyzer.dart';
import 'pose_3d_cache.dart';

enum Pose3dJobStatus { running, cancelling, completed, cancelled, failed }

/// App-owned work, independent of the route that displays it.
final class Pose3dJob extends ChangeNotifier {
  Pose3dJob(this.project, this.settings);
  final AnalysisProject project;
  Pose3dSettings settings;
  Future<void> Function(Pose3dComparison)? persist;
  Object? cacheError;
  Pose3dJobStatus status = Pose3dJobStatus.cancelled;
  Pose3dComparison? result;
  String? savedProjectId;
  Object? error;
  double progress = 0;
  final _inferenceClock = Stopwatch();
  Duration? get estimatedRemaining =>
      status == Pose3dJobStatus.running && _inferenceClock.isRunning
      ? estimatePose3dRemaining(progress, _inferenceClock.elapsed)
      : null;
  String side = 'A';
  Pose3dAnalyzer? _analyzer;
  Future<void>? completion;
  bool get busy =>
      status == Pose3dJobStatus.running || status == Pose3dJobStatus.cancelling;
  void start() {
    if (busy) return;
    status = Pose3dJobStatus.running;
    error = null;
    cacheError = null;
    progress = 0;
    side = 'A+B';
    _inferenceClock
      ..stop()
      ..reset();
    final analyzer = _analyzer = Pose3dAnalyzer();
    completion = _run(analyzer);
    notifyListeners();
  }

  Future<void> _run(Pose3dAnalyzer analyzer) async {
    try {
      result = await analyzer.analyze(project, settings, (p, s) {
        progress = p;
        side = s;
        notifyListeners();
      }, onInferenceStarted: _inferenceClock.start);
      try {
        await persist?.call(result!);
      } catch (e) {
        cacheError = e;
      }
      status = Pose3dJobStatus.completed;
    } on Pose3dCancelled {
      status = Pose3dJobStatus.cancelled;
    } catch (e) {
      error = e;
      status = Pose3dJobStatus.failed;
    } finally {
      _inferenceClock.stop();
      _analyzer = null;
      notifyListeners();
    }
  }

  void cancel() {
    if (!busy || status == Pose3dJobStatus.cancelling) return;
    _analyzer?.cancelled = true;
    status = Pose3dJobStatus.cancelling;
    notifyListeners();
  }

  void updateSettings(Pose3dSettings value) {
    settings = value;
    notifyListeners();
  }

  bool matches(AnalysisProject other) {
    bool same(AnalysisTrack a, AnalysisTrack b) =>
        a.source.path == b.source.path &&
        a.mediaDuration == b.mediaDuration &&
        a.trim.start == b.trim.start &&
        a.trim.end == b.trim.end &&
        a.rate.value == b.rate.value;
    return same(project.trackA, other.trackA) &&
        same(project.trackB, other.trackB);
  }
}

final class Pose3dJobs extends ChangeNotifier {
  static final instance = Pose3dJobs();
  Pose3dJob? current;
  final _projects =
      <String, ({AnalysisProject source, AnalysisProject saved})>{};

  bool _same(AnalysisProject a, AnalysisProject b) {
    bool track(AnalysisTrack x, AnalysisTrack y) =>
        x.source.path == y.source.path &&
        x.mediaDuration == y.mediaDuration &&
        x.trim.start == y.trim.start &&
        x.trim.end == y.trim.end &&
        x.rate.value == y.rate.value;
    return track(a.trackA, b.trackA) && track(a.trackB, b.trackB);
  }

  /// Bind the inference snapshot to durable project media, including while running.
  Future<void> bindProject(
    String id,
    AnalysisProject source,
    AnalysisProject saved,
  ) async {
    final previous = _projects[id];
    _projects[id] = (
      source: previous != null && _same(previous.saved, saved)
          ? previous.source
          : source,
      saved: saved,
    );
    final active = current;
    final ownsResult =
        active != null &&
        active.matches(source) &&
        (active.savedProjectId == null || active.savedProjectId == id);
    if (ownsResult) active.savedProjectId = id;
    final result = ownsResult ? active.result : null;
    final available =
        result ??
        await Pose3dCache.load(source, savedProjectId: id) ??
        await Pose3dCache.load(source);
    if (available != null) {
      await Pose3dCache.save(
        Pose3dComparison(saved, available.settings, available.a, available.b),
        savedProjectId: id,
      );
    }
  }

  Future<void> _persist(Pose3dJob job, Pose3dComparison result) async {
    // Project data is durable and independent of the single recent-result cache.
    for (final entry in _projects.entries.toList()) {
      if (entry.key != job.savedProjectId) continue;
      if (_same(entry.value.source, result.project) ||
          _same(entry.value.saved, result.project)) {
        await Pose3dCache.save(
          Pose3dComparison(
            entry.value.saved,
            result.settings,
            result.a,
            result.b,
          ),
          savedProjectId: entry.key,
        );
      }
    }
    await Pose3dCache.save(result);
  }

  Future<Pose3dJob> getOrStart(
    AnalysisProject project,
    Pose3dSettings settings, {
    String? savedProjectId,
  }) async {
    if (savedProjectId != null && !_projects.containsKey(savedProjectId)) {
      await bindProject(savedProjectId, project, project);
    }
    final old = current;
    if (old != null && old.busy) return old;
    if (old != null &&
        old.result != null &&
        old.matches(project) &&
        old.savedProjectId == savedProjectId) {
      old.updateSettings(settings);
      return old;
    }
    old?.removeListener(notifyListeners);
    old?.dispose();
    final job = current = Pose3dJob(project, settings);
    job.savedProjectId = savedProjectId;
    job.persist = (result) => _persist(job, result);
    final binding = _projects[savedProjectId];
    final cacheProject = binding != null && _same(binding.source, project)
        ? binding.saved
        : project;
    final cached =
        (savedProjectId == null
            ? null
            : await Pose3dCache.load(
                cacheProject,
                savedProjectId: savedProjectId,
              )) ??
        await Pose3dCache.load(project);
    if (cached != null) {
      job.result = Pose3dComparison(
        project,
        cached.settings,
        cached.a,
        cached.b,
      );
      job.status = Pose3dJobStatus.completed;
      job.progress = 1;
    }
    job.addListener(notifyListeners);
    if (cached == null) {
      job.start();
    } else {
      notifyListeners();
    }
    return job;
  }
}
