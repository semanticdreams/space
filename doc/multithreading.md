Multithreading strategy
=======================

Goals
- Keep SDL input, OpenGL, and the Lua/Fennel VM on the main thread to avoid context/VM contention.
- Offload CPU-heavy, non-GL work (asset decode, data prep, physics stepping later) to workers.
- Use message passing and snapshot swaps instead of fine-grained locks; keep shared data POD-like.

Execution model
- Main thread: owns SDL event pump, GL context, the Lua state, and runs `app.update` + renderers.
- Worker pool: small job system in C++ (thread pool + lock-free/mtx queue). Jobs return immutable results; main thread polls/drains completions each frame before rendering.
- GL calls remain on the main thread; workers only prepare CPU data. Swaps happen by replacing buffers/handles atomically on the main thread.

Workload placement
- Assets: load/decode textures/meshes/audio on workers. Return raw bytes/CPU meshes; main thread uploads to GL or hands to runtime structures.
- Physics: keep Bullet on the main thread until ownership is refactored. Later, move stepping to a physics thread with a command queue (add/remove/impulses) and publish double-buffered transforms back to the main thread for rendering/UI. No direct `btRigidBody` access from Fennel.
- Render prep: workers may build geometry/text batches into transient buffers, but only the main thread mutates `VectorBuffer`/`DrawBatcher` or calls GL. Swap whole buffers on the main thread per frame.
- Audio: decoding/streaming on workers; OpenAL context calls (play/stop/listener updates) stay on the main thread. Feed ready-to-queue buffers through the job/completion path.

Synchronization guidelines
- Prefer queues + snapshot swaps over locks. Keep shared snapshots immutable once published.
- Avoid touching Lua/Fennel or GL from workers. Workers communicate via C++ queues/buffers only.
- Batch state changes: apply completed job results during the `app.update` frame loop before issuing draws.

Phased adoption
1) Add engine-level job system + Lua binding for enqueue/poll; use it first for background asset loads.
2) Audit physics entry points in Fennel and route through a physics-ownership layer to enable an off-thread physics step later.
3) Once stable, offload heavy render prep (text shaping, static geometry generation) by producing swap-ready buffers, integrated on the main thread.
4) Keep profiling (FrameProfiler) to choose the next offload target and validate wins after each phase.

Job payload pipeline (current)
- Workers return `JobResult::payload` as a raw buffer (`void* data`, `size_bytes`, `alignment`, `element_size`, `unique_ptr` deleter). The worker allocates and fills the buffer; the main thread adopts it without copying. RAII cleanup still runs on failures.
- Metadata travels with the buffer so consumers can validate before casting; check `alignment` and `element_size` against the desired type before reinterpreting.
- Textures/audio now move stb/WAV buffers straight through to GL/OpenAL. Cubemaps currently memcpy faces into one contiguous block for upload; if that ever shows up in profiles, per-face payloads can remove that copy.
- No refcount overhead (unlike `shared_ptr`), no implicit byte copies (unlike the old `std::vector<uint8_t>` path); performance matches raw C buffers with fewer leak/double-free footguns.

Passing typed data (e.g., vertices) with zero copies
- Build buffers in the job: `auto verts = std::make_unique<float[]>(count); … result.payload = NativePayload::from_array(std::move(verts), count);`.
- Main thread: assert `element_size == sizeof(float)` and `alignment >= alignof(float)`, then `static_cast<float*>(payload.data)` with count `size_bytes / sizeof(float)`.
- `std::vector<T>` can be wrapped via `from_owned` with a deleter that frees the vector; never resize after capturing `data()`.

Reusing existing buffers
- If you want to reuse a persistent vector/handle buffer, pass a borrowed span (pointer + capacity + element size) into the job and guarantee exclusive access while it writes.
- Jobs must not resize; if capacity is insufficient, fail or request a larger buffer. After completion, set the vector size on the main thread—no copy, same allocation.
