# Remote Control (Debugging)

Run the app with a ZeroMQ endpoint to evaluate Fennel code inside the live process:

```
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m main --remote-control=ipc:///tmp/space-rc.sock
```

Send code from another process using the bundled Fennel client:

```
./build/space -m tools.remote-control-client:main -- --endpoint ipc:///tmp/space-rc.sock -c "(+ 1 2)"
```

This executes in `_G` (so `app`, `logging`, etc. are available) and replies with `ok ...` or `error ...`.
Only enable this on trusted machines; it executes arbitrary code in the running app.

Async results are supported via the `remote_control` helper exposed to the eval environment:

```
;; returns a request id immediately
(local id (remote_control.create))
(app.engine.events.window-resized:connect
  (fn [e]
    (remote_control.resolve id {:width e.width :height e.height})))
id
```

Poll from a client:

```
./build/space -m tools.remote-control-client:main -- --endpoint ipc:///tmp/space-rc.sock \
  -c "(remote_control.poll \"<id>\")"
```

To exercise the async flow against a live app, run the heavy test script:

```
scripts/remote-control-heavy.sh ipc:///tmp/space-rc.sock
```
