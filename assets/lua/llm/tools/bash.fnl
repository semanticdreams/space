(local shell (require :shell))

(local tool-name "bash")

(fn require-shell []
    (assert (and shell shell.bash) "bash tool requires the shell binding with bash")
    shell)

(fn bash [args ctx]
    (local options (or args {}))
    (local command options.command)
    (assert command "bash requires command")
    (assert (= (type command) :string) "bash.command must be a string")

    (local timeout options.timeout)
    (assert timeout "bash requires timeout")
    (assert (= (type timeout) :number) "bash.timeout must be a number")

    (local context (or ctx {}))
    (local cwd (or options.cwd context.cwd))
    (local binding (require-shell))
    (local shell-opts {:command command
                       :timeout timeout})
    (when cwd
        (set shell-opts.cwd cwd))
    (local (ok result) (pcall binding.bash shell-opts))
    (if (not ok)
        (error (.. "bash failed: " result)))

    {:tool tool-name
     :command command
     :timeout timeout
     :stdout result.stdout
     :stderr result.stderr
     :exit_code result.exit_code
     :signal result.signal
     :timed_out result.timed_out
     :duration_ms result.duration_ms})

{:name tool-name
 :description "Run a bash command with a timeout, returning stdout and stderr."
 :parameters {:type "object"
              :properties {:command {:type "string"
                                     :description "Bash command to run with `bash -lc`"}
                           :timeout {:type "number"
                                     :description "Timeout in seconds"}}
              :required ["command" "timeout"]
              :additionalProperties false}
 :strict true
 :call bash}
