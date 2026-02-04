(local RateLimiter (require :rate-limiter))
(local math math)

(fn test-acquire-delays []
  (local limiter (RateLimiter {:limit 2 :window_ms 100}))
  (local first (limiter.acquire))
  (local second (limiter.acquire))
  (local third (limiter.acquire))
  (assert (= first 0) "first acquire should not be delayed")
  (assert (= second 0) "second acquire should not be delayed within the limit")
  (assert (>= third 90) "third acquire should be delayed by roughly a window"))

(fn test-reset []
  (local limiter (RateLimiter {:limit 1 :window_ms 200}))
  (limiter.acquire)
  (assert (> (limiter.acquire) 0) "second acquire should be delayed when limit is 1")
  (limiter.reset)
  (assert (= (limiter.acquire) 0) "acquire should be immediate after reset"))

(local tests [{ :name "rate limiter enforces window delay" :fn test-acquire-delays}
 { :name "rate limiter reset clears history" :fn test-reset}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "rate-limiter"
                       :tests tests})))

{:name "rate-limiter"
 :tests tests
 :main main}
