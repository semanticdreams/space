(local Exec (require :llm/providers/codex/exec))
(local ThreadModule (require :llm/providers/codex/thread))

(fn start-thread [self options]
  (ThreadModule.Thread self.exec self.options (or options {}) nil))

(fn resume-thread [self id options]
  (ThreadModule.Thread self.exec self.options (or options {}) id))

(fn Codex [options]
  (local resolved (or options {}))
  {:exec (Exec.CodexExec resolved)
   :options resolved
   :start-thread start-thread
   :resume-thread resume-thread})

{:Codex Codex}
