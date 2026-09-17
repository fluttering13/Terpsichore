import 'dart:async';

/// Start both independent jobs and wait for both to finish, including cleanup.
/// Future.sync also captures a synchronous failure without skipping the other job.
Future<List<T>> runParallelPoseJobs<T>(
  Future<T> Function() a,
  Future<T> Function() b,
) => Future.wait([Future<T>.sync(a), Future<T>.sync(b)], eagerError: false);
