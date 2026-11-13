# Mac reply worker

`main.swift` is the on-device reply worker. Run it from the repository root so it finds the root `PROMPT.md` and keeps its cursor in the root `last_id.txt`.

```sh
swiftc -parse-as-library -o jesus-backend backend/main.swift
./jesus-backend
```

Requires a Mac and a Swift toolchain with Apple Foundation Models; the model must be available on that Mac. The prompt loads once at startup, so restart after changing it.

## Message flow

1. Poll `/api/history` every five seconds.
2. When unanswered visitor messages exist, wait 700 ms to catch quick follow-ups.
3. Generate one reply for the entire batch. If more visitors write while the model is generating, refresh the draft with those messages included (up to three coalescing passes).
4. Post the reply once. Advance `last_id.txt` only after the post succeeds. Failed generation or posting leaves the batch eligible for retry.

The model sees the twelve messages before the batch plus the complete batch. Since the public site labels everyone as `Visitor`, the prompt tells Jesus not to assume several messages came from the same person.

The worker sends `/api/heartbeat` at startup and every two minutes. Do not run the legacy heartbeat helpers at the same time; they can report an open line while this worker is down.
