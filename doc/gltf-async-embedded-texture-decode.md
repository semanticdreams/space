# Async Embedded Texture Decode Plan

Goal: reduce the remaining main-thread spike during glTF load by moving embedded image decoding
off-thread, leaving only GL upload on the main thread.

Current behavior
- `gltf-mesh` calls `textures.load-texture-from-bytes` for embedded image buffer views.
- `load-texture-from-bytes` uses `stbi_load_from_memory` on the main thread.
- Texture generation and GL upload run on the main thread as part of that call.

Proposed change
1) Add a new jobs handler that decodes image bytes to raw pixels.
   - Location: `src/resource_manager.cpp` or `src/cgltf_jobs.cpp` (preferred: `resource_manager.cpp`
     alongside `load_texture` / `load_cubemap` jobs).
   - Job kind: `decode_image_bytes` (or `decode_texture_bytes`).
   - Input payload: raw bytes of the image (already extracted from the glTF buffer view).
   - Output: `JobResult::payload` with the pixel bytes and `aux_a/aux_b/aux_c` set to width/height/channels.
   - Use `stbi_load_from_memory` inside the job handler; free pixels via `stbi_image_free`
     using `NativePayload::from_owned`.

2) Add a Lua binding to request decode and finish on the main thread.
   - Option A: expose a new `textures.load-texture-from-bytes-async(name, bytes, callback)`.
     - Submit decode job, then in callback: allocate `Texture2D`, call `load_from_pixels`,
       `generate()`, and return the texture.
   - Option B: add a `jobs` callback path used by `gltf-mesh` directly
     to convert the decoded pixels into a texture.
   - Keep GPU upload on main thread; only decoding should happen in the job.

3) Update `gltf-mesh` to use the async decode path for embedded images.
   - For `image-bytes`, submit the decode job and register a callback that
     replaces the texture in the batch when ready.
   - Until ready, keep the batch hidden or render with a placeholder texture.
   - Make sure cancellation on `drop` does not leak decoded buffers.

4) Add tests (not in the main test suite).
   - A dedicated Fennel test module that:
     - Submits a decode job with a known embedded image (e.g. from `BoxTextured.glb`).
     - Asserts `width/height/channels` are returned and byte count matches.
     - Creates a texture on the main thread using returned pixels.
   - Keep this test opt-in, similar to other slow cgltf tests.

Notes
- The job result payload already supports binary data via `NativePayload`,
  so no extra copy into Lua tables is needed.
- If you reuse `ResourceManager` to finish textures, follow the same pattern as
  `load_texture` job handling to avoid duplicating GL upload logic.
