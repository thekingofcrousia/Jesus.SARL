# Mac AI telephone bridge

`main.swift` is the AI mediator for the Jesus-side endpoint. Run it from the repository root so it finds the root `PROMPT.md` and keeps its cursor in the root `last_id.txt`. The model composes messages for the endpoint; it does not claim the machine is Jesus or that generated text is verified revelation.

```sh
swiftc -parse-as-library -o jesus-backend backend/main.swift
./jesus-backend
```

Requires a Mac and a Swift toolchain with Apple Foundation Models; the model must be available on that Mac. The prompt loads once at startup, so restart after changing it.

## Message flow

1. Poll `/api/history` every three seconds.
2. When unanswered visitor messages exist, wait 700 ms to catch quick follow-ups.
3. Generate one Jesus-side message for the entire batch. If more visitors write while the model is generating, refresh the draft with those messages included (up to three coalescing passes).
4. Verify the batch against current history before posting. If history cannot be checked, defer the reply and retry on the next poll.
5. Post one reply and advance `last_id.txt` only after the post succeeds. Failed generation or posting leaves the batch eligible for retry.

The model sees the twelve messages before the batch plus the complete batch. Since the public site labels everyone as `Visitor`, the prompt directs the machine not to assume several messages came from the same person.

The worker sends `/api/heartbeat` at startup and every two minutes. Do not run the legacy heartbeat helpers at the same time; they can report the line open while this worker is down.

The implementation of the `/api` service is deployed separately and is not in this repository.
