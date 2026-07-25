---
description: Memory, lifecycle, and concurrency audit required after every change
globs: "**/*.{rs,swift}"
---

# Resource Standards

Run this audit after writing code, before opening the work for review. It is not a release-time activity.

## Memory
- RSS returns to baseline after a full cycle: idle, work, idle.
- RSS returns to baseline after switching or releasing a model.
- Dropping a reference is not proof memory was freed. Verify GPU and accelerator buffers are actually returned.
- Record peak RSS when two large models can be resident at once.

## Lifecycle
- Every spawned process dies on idle timeout and on app quit. No orphan survives killing the app.
- Every timer scheduled is invalidated on the paths that end its purpose, including error and cancel paths.
- Every `AsyncStream` continuation is finished. Every consumer task is cancelled.
- Every event tap, observer, and audio unit is torn down when not in use.
- Teardown is idempotent. It runs on the success path, the error path, and the cancel path.

## Concurrency
- Every async path that can be superseded carries a generation guard. Reuse the existing pattern rather than inventing another.
- Snapshot state by value before crossing into a detached task. Never read shared mutable state from inside one.
- Check for cancellation after every suspension point in a long task.
- Shared mutable state is behind an actor or a lock. Locks are never held across a suspension point.

## Main thread
- No inference, file I/O, or network on the main actor.
- Confirm with a profiler's hang detection, not by reading the code.
