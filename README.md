# Jesus.SARL

A public AI telephone bridge for a faith-inspired visitor reaching out to Jesus Christ.

## How the system fits together

- `index.html` is the GitHub Pages frontend. It reads and writes through the existing `/api` service.
- `/api/history`, `/api/message`, `/api/status`, and `/api/heartbeat` are provided by the separate API deployment.
- `PROMPT.md` defines the machine's role and message style: the AI is the bridge; Jesus is the faith endpoint. Generated messages are AI-mediated, not verified divine revelation.
- `backend/main.swift` polls the API, batches unanswered visitor messages, asks Apple Foundation Models to compose one Jesus-side message for the batch, and posts it under the endpoint label `Jesus`.
- The worker itself sends the heartbeat. A separate heartbeat-only process can make the line look online after the reply worker has stopped, so do not run one alongside the worker.

The conversation history is public. Do not send private details through this line.

## Run the Mac reply worker

From the repository root on the Mac with Apple Foundation Models available:

```sh
swiftc -parse-as-library -o jesus-backend backend/main.swift
./jesus-backend
```

The worker reads `PROMPT.md` and stores its cursor in the untracked `last_id.txt` file in the current directory. Keep that file with the running installation so restarts do not replay old messages. Restart the worker after changing the prompt.

See [backend/README.md](backend/README.md) for the message batching and runtime details.
