# Process Module

The `process` module provides facilities for launching and managing external programs from Fennel/Lua code. It supports both synchronous (blocking) and asynchronous (non-blocking) execution modes with full control over stdin/stdout/stderr, environment variables, working directory, and process lifecycle.

## Usage

```fennel
(local process (require :process))
```

## API Reference

### process.run

Synchronously executes a command and waits for completion.

```fennel
(local result (process.run opts))
```

**Options table:**

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `args` | table | yes | List of strings: command and arguments (e.g., `["ls" "-la"]`) |
| `cwd` | string | no | Working directory for the process |
| `env` | table | no | Environment variables to set (key-value pairs) |
| `clear-env` | boolean | no | If true, clears inherited environment before applying `env` |
| `stdin` | string | no | Data to write to the process's stdin |
| `timeout` | number | no | Timeout in seconds; process is killed if exceeded |
| `merge-stderr` | boolean | no | If true, stderr is redirected to stdout |

**Returns:** Result table (see [Result Table](#result-table))

### process.spawn

Asynchronously spawns a process without blocking.

```fennel
(local id (process.spawn opts callback))
```

**Parameters:**
- `opts` - Options table (same as `process.run`)
- `callback` - Optional function called with result when process completes

**Returns:** Process ID (integer) for use with other functions

When a callback is provided, it will be invoked via the engine's callback dispatch system when the process completes. Without a callback, use `process.poll` or `process.wait` to retrieve results.

### process.write

Writes data to a spawned process's stdin.

```fennel
(local bytes-written (process.write id data))
```

**Parameters:**
- `id` - Process ID from `process.spawn`
- `data` - String to write

**Returns:** Number of bytes written

**Throws:** Error if process ID is invalid or stdin is closed

### process.close-stdin

Closes the stdin pipe of a spawned process, signaling EOF.

```fennel
(local success (process.close-stdin id))
```

**Parameters:**
- `id` - Process ID from `process.spawn`

**Returns:** `true` if stdin was open and is now closed, `false` otherwise

### process.kill

Sends a signal to a spawned process.

```fennel
(process.kill id)        ; sends SIGTERM (15)
(process.kill id 9)      ; sends SIGKILL (9)
```

**Parameters:**
- `id` - Process ID from `process.spawn`
- `signal` - Optional signal number (default: SIGTERM/15)

**Returns:** `true` if signal was sent successfully, `false` otherwise

### process.running

Checks if a spawned process is still running.

```fennel
(if (process.running id)
    (print "still running")
    (print "finished"))
```

**Parameters:**
- `id` - Process ID from `process.spawn`

**Returns:** `true` if process is running, `false` if finished or invalid ID

### process.wait

Blocks until a spawned process completes and returns its result.

```fennel
(local result (process.wait id))
```

**Parameters:**
- `id` - Process ID from `process.spawn`

**Returns:** Result table (see [Result Table](#result-table))

**Throws:** Error if process ID is invalid

Note: If the process had a callback, the callback is unregistered and not invoked.

### process.poll

Polls for completed processes that were spawned without callbacks.

```fennel
(local results (process.poll))
(local results (process.poll max-count))
```

**Parameters:**
- `max-count` - Optional maximum number of results to return (0 = unlimited)

**Returns:** Table of result tables, each with an additional `id` field

Processes spawned with callbacks are not included in poll results; they are dispatched through the callback system instead.

## Result Table

All completion functions return a result table with these fields:

| Field | Type | Description |
|-------|------|-------------|
| `exit-code` | integer | Process exit code (0 typically means success) |
| `signal` | integer or nil | Signal number if killed by signal, nil otherwise |
| `timed-out` | boolean | `true` if process was killed due to timeout |
| `stdout` | string | Captured stdout output |
| `stderr` | string | Captured stderr output (empty if `merge-stderr` was true) |
| `duration-ms` | integer | Execution time in milliseconds |

Exit code conventions:
- 0: Success
- 1-125: Command-specific error codes
- 126: Command found but not executable (e.g., permission denied)
- 127: Command not found
- 128+N: Killed by signal N (e.g., 137 = 128+9 = SIGKILL)

## Examples

### Simple command execution

```fennel
(local result (process.run {:args ["echo" "hello world"]}))
(print result.stdout)  ; "hello world\n"
(print result.exit-code)  ; 0
```

### Command with working directory and environment

```fennel
(local result (process.run {:args ["sh" "-c" "echo $MY_VAR from $(pwd)"]
                            :cwd "/tmp"
                            :env {:MY_VAR "test"}}))
(print result.stdout)  ; "test from /tmp\n"
```

### Piping data to stdin

```fennel
(local result (process.run {:args ["cat"]
                            :stdin "data from fennel"}))
(print result.stdout)  ; "data from fennel"
```

### Timeout handling

```fennel
(local result (process.run {:args ["sleep" "60"]
                            :timeout 1}))
(if result.timed-out
    (print "command timed out")
    (print "command completed"))
```

### Async execution with callback

```fennel
(process.spawn {:args ["long-running-task"]}
               (fn [result]
                 (print "Task finished with exit code:" result.exit-code)))
```

### Interactive async process

```fennel
(local id (process.spawn {:args ["cat"]}))

;; Write data incrementally
(process.write id "line 1\n")
(process.write id "line 2\n")

;; Signal end of input
(process.close-stdin id)

;; Wait for completion
(local result (process.wait id))
(print result.stdout)  ; "line 1\nline 2\n"
```

### Multiple concurrent processes

```fennel
(local ids [])
(for [i 1 5]
  (table.insert ids (process.spawn {:args ["echo" (tostring i)]})))

;; Wait for all to complete
(each [_ id (ipairs ids)]
  (local result (process.wait id))
  (print result.stdout))
```

### Polling for completed processes

```fennel
;; Spawn several processes without callbacks
(process.spawn {:args ["echo" "one"]})
(process.spawn {:args ["echo" "two"]})
(process.spawn {:args ["echo" "three"]})

;; Later, poll for results
(local results (process.poll))
(each [_ r (ipairs results)]
  (print (.. "Process " r.id " output: " r.stdout)))
```

### Killing a runaway process

```fennel
(local id (process.spawn {:args ["sleep" "3600"]}))

;; Do some work...

;; Decide to cancel
(when (process.running id)
  (process.kill id)  ; SIGTERM
  (local result (process.wait id))
  (print "Killed, signal:" result.signal))
```

## Implementation Notes

### Files

- `src/lua_process.h` - Header declaring binding functions
- `src/lua_process.cpp` - Implementation (~750 lines)
- `src/lua_runtime.cpp` - Registers `lua_bind_process`
- `src/engine.cpp` - Calls `lua_process_dispatch` and `lua_process_drop`

### Architecture

The module uses POSIX `fork`/`exec` for process creation:

1. **Synchronous mode** (`process.run`): Forks, sets up pipes, executes the command, and polls for output/completion in a loop until the child exits or times out.

2. **Asynchronous mode** (`process.spawn`): Forks and returns immediately. A `ProcessManager` singleton tracks all spawned processes. Each frame, `lua_process_dispatch` is called from the engine loop to:
   - Poll all running processes for output
   - Check for completion or timeout
   - Enqueue callbacks for finished processes via `lua_callbacks`

### Process Groups

Both parent and child call `setpgid` to establish process groups. This allows `killpg` to terminate the entire process tree (the spawned process and any children it may have created), not just the top-level process.

### Non-blocking I/O

All pipe file descriptors are set to non-blocking mode using `fcntl(F_SETFL, O_NONBLOCK)`. This allows the parent to interleave reading stdout/stderr without deadlocking when buffers fill.

### Timeout Handling

When a timeout expires:
1. `SIGTERM` is sent to the process group
2. A 200ms grace period allows graceful shutdown
3. If still running, `SIGKILL` is sent
4. The process is reaped with `waitpid`

### Cleanup

`lua_process_drop` (called during engine shutdown) kills all remaining spawned processes with `SIGKILL` and closes all open file descriptors to prevent resource leaks.

## Testing

Tests are in `assets/lua/tests/test-process.fnl` (34 tests) covering:
- Basic sync execution
- Exit codes and signals
- Stdout/stderr capture and merging
- Stdin piping
- Working directory
- Environment variables
- Timeout behavior
- Async spawn/wait/poll
- Process killing
- Interactive stdin writing
- Error handling
- Concurrent processes

Run with:
```sh
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-process:main
```
