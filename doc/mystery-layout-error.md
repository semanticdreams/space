## Error message

```
invalid key to 'next'                                                                                                                                                                          
stack traceback:                                                                                                                                                                               
        [C]: in function 'base.next'                                                                                                                                                           
        /home/sam/pj/space/build/../assets/lua/bucket-queue.fnl:36: in method 'iterate'                                                                                                        
        /home/sam/pj/space/build/../assets/lua/layout.fnl:423: in method 'update'                                                                                                              
        /home/sam/pj/space/build/../assets/lua/hud.fnl:347: in function </home/sam/pj/space/build/../assets/lua/hud.fnl:347>                                                                   
        (...tail calls...)                                                                                                                                                                     
        /home/sam/pj/space/build/../assets/lua/frame-profiler.fnl:34: in function </home/sam/pj/space/build/../assets/lua/frame-profiler.fnl:31>                                               
        (...tail calls...)                                                                                                                                                                     
        /home/sam/pj/space/build/../assets/lua/main.fnl:508: in local 'cb'                                                                                                                     
        /home/sam/pj/space/build/../assets/lua/signal.fnl:7: in function </home/sam/pj/space/build/../assets/lua/signal.fnl:4>                                                                 
        [C]: in method 'run'                                                                                                                                                                   
        /home/sam/pj/space/build/../assets/lua/main.fnl:588: in main chunk                                                                                                                     
        (...tail calls...)                                                                                                                                                                     
        [C]: in function 'base.require'                                                                                                                                                        
        [string "require("main")"]:1: in main chunk                                                                                                                                            
Aborted (core dumped) 
```

## Debug logging

We added guarded queue iteration logging so the next occurrence captures more context.

- Log file: `layout-queue.log` in `appdirs.user-log-dir "space"` (same base dir as `space.log`).
- Logger module: `assets/lua/layout-debug-log.fnl`.
- Hook point: `assets/lua/bucket-queue.fnl` wraps `next` in `pcall` and logs failures.
- Logged fields: error message, queue label, queue depth count, bucket table type/value/count,
  key type/value, key name/depth/root/parent/ancestor names, key membership in bucket and lookup depth,
  depth, frame-id, traceback.

When the error happens again, attach `layout-queue.log` along with the stack trace.

## Cleanup plan (remove debug hooks)

When no longer needed:

1) Remove the debug module: `assets/lua/layout-debug-log.fnl`.
2) Revert the guarded `iterate` loop in `assets/lua/bucket-queue.fnl` back to a simple `pairs` iteration.

If you added any temporary tests to reproduce the issue, remove them from `assets/lua/tests/` and `assets/lua/tests/fast.fnl`.
