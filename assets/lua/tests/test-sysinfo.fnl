(local tests [])
(local sysinfo (require :sysinfo))
(local process (require :process))

(fn trim [s]
  (if (not s)
      ""
      (or (string.match s "^%s*(.-)%s*$") "")))

(fn assert-percent-range [value msg]
  (assert (= (type value) "number") msg)
  (assert (>= value 0.0) msg)
  (assert (<= value 100.0) msg))

(fn test-platform []
  (local p (sysinfo.platform))
  (assert (= (type p) "table") "platform should return a table")
  (assert (= (type p.os) "string") "platform.os should be a string")
  (assert (= (type p.arch) "string") "platform.arch should be a string")
  (assert (= (type p.features) "table") "platform.features should be a table")
  (assert (or (= p.os "linux") (= p.os "windows") (= p.os "macos")) "unexpected platform.os"))

(fn test-system-cpu-warmup []
  (local sys (sysinfo.system))
  (local first (sys:cpu-usage))
  (assert first.warmup "first cpu sample should be warmup")
  (assert (= first.percent nil) "first cpu sample percent should be nil")
  (sysinfo.sleep 0.05)
  (local second (sys:cpu-usage))
  (assert (not second.warmup) "second cpu sample should not be warmup")
  (assert-percent-range second.percent "system cpu percent should be 0..100")
  (assert (> second.interval 0.0) "system cpu interval should be > 0"))

(fn test-system-cpu-times-and-memory []
  (local sys (sysinfo.system))
  (assert (sys:refresh) "sys:refresh should succeed")
  (local times (sys:cpu-times))
  (assert (= (type times) "table") "cpu-times should be a table")

  (local mem (sys:mem-virtual))
  (assert (= (type mem) "table") "mem-virtual should be a table")
  (assert (= (type mem.total) "number") "mem-virtual total should be numeric")
  (assert (> mem.total 0) "mem-virtual total should be > 0")
  (when mem.percent
    (assert-percent-range mem.percent "mem percent should be 0..100")))

(fn test-system-refresh-counts-as-baseline []
  (local sys (sysinfo.system))
  (assert (sys:refresh) "first refresh should succeed")
  (sysinfo.sleep 0.05)
  (assert (sys:refresh) "second refresh should succeed")
  (sysinfo.sleep 0.05)
  (local usage (sys:cpu-usage))
  (assert (not usage.warmup) "cpu-usage should be warm after refresh samples")
  (assert-percent-range usage.percent "cpu-usage percent should be 0..100 after refresh samples"))

(fn test-process-current []
  (local sys (sysinfo.system))
  (local p (sys:process-current))
  (assert (= (type p.pid) "number") "process-current pid should be numeric")
  (assert (> p.pid 0) "process-current pid should be positive")
  (assert (p:exists) "current process should exist")

  (local name (p:name))
  (when name
    (assert (= (type name) "string") "process name should be string when present"))

  (local c1 (p:cpu))
  (assert c1.warmup "first process cpu sample should be warmup")
  (assert (= c1.percent nil) "first process cpu percent should be nil")
  (sysinfo.sleep 0.05)
  (local c2 (p:cpu))
  (assert (not c2.warmup) "second process cpu sample should not be warmup")
  (assert-percent-range c2.percent "process cpu percent should be 0..100")
  (assert (> c2.interval 0.0) "process cpu interval should be > 0")

  (local times (p:cpu-times))
  (assert (= (type times) "table") "process cpu-times should be a table")
  (when times.user
    (assert (= (type times.user) "number") "process cpu-times user should be numeric when present"))
  (when times.system
    (assert (= (type times.system) "number") "process cpu-times system should be numeric when present"))

  (local mem (p:mem))
  (assert (= (type mem) "table") "process mem should be a table")
  (when mem.rss
    (assert (> mem.rss 0) "process rss should be > 0 when present"))
  (when mem.percent
    (assert-percent-range mem.percent "process mem percent should be 0..100")))

(fn test-process-refresh-counts-as-baseline []
  (local sys (sysinfo.system))
  (local p (sys:process-current))
  (assert (p:refresh) "first process refresh should succeed")
  (sysinfo.sleep 0.05)
  (assert (p:refresh) "second process refresh should succeed")
  (sysinfo.sleep 0.05)
  (local c (p:cpu))
  (assert (not c.warmup) "process cpu should be warm after refresh samples")
  (assert-percent-range c.percent "process cpu percent should be 0..100 after refresh samples"))

(fn test-process-by-pid-and-list []
  (local sys (sysinfo.system))
  (local self (sys:process-current))

  (local by-pid (sys:process self.pid))
  (assert by-pid "sys:process should resolve current pid")
  (assert (= by-pid.pid self.pid) "sys:process pid should match")

  (assert (= (sys:process -1) nil) "invalid pid should return nil")

  (local list (sys:process-list {:limit 16}))
  (assert (= (type list) "table") "process-list should return table")
  (assert (<= (# list) 16) "process-list should honor limit")

  (local filtered (sys:process-list {:name "space" :limit 8}))
  (assert (= (type filtered) "table") "filtered process-list should return table")
  (assert (<= (# filtered) 8) "filtered process-list should honor limit")

  (var candidate nil)
  (each [_ info (ipairs list)]
    (when (and (not candidate)
               info
               info.pid
               (not (= info.pid self.pid)))
      (set candidate info.pid)))
  (when candidate
    (local other (sys:process candidate))
    (assert other "sys:process should resolve candidate pid")
    (assert (other:exists) "candidate pid should exist")))

(table.insert tests {:name "sysinfo platform" :fn test-platform})
(table.insert tests {:name "sysinfo system cpu warmup" :fn test-system-cpu-warmup})
(table.insert tests {:name "sysinfo system cpu-times and memory" :fn test-system-cpu-times-and-memory})
(table.insert tests {:name "sysinfo system refresh baseline" :fn test-system-refresh-counts-as-baseline})
(table.insert tests {:name "sysinfo process-current" :fn test-process-current})
(table.insert tests {:name "sysinfo process refresh baseline" :fn test-process-refresh-counts-as-baseline})
(table.insert tests {:name "sysinfo process by pid and list" :fn test-process-by-pid-and-list})

tests
