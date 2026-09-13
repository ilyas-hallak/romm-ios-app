# Feature request: a REST endpoint to start a library scan

Reading a scan already works over REST.
`GET /api/tasks/status` and `GET /api/tasks/{task_id}` give a client everything it needs to follow or pick up a running scan.

Starting one does not.
`scan_library` is declared `manual_run=False`, so `POST /api/tasks/run/scan_library` answers 400, and the only working path is the `scan` Socket.IO event.

That is a problem for non-browser clients.
The socket's `connect` handler resolves the user through the `romm_session` cookie only, so a client authenticating with `Authorization: Bearer` (device flow or a client token) has no way to start a scan.
It has to ask the user for a username and password a second time just to trade them for a session cookie, which is a poor thing to ask of someone who deliberately signed in without a password.

## Proposal

`POST /api/tasks/scan`, scope `tasks.run`, same Bearer/Basic auth as the rest of the API.

Request body mirrors the existing socket payload, so nothing new has to be specified:

```json
{
  "platforms": [1, 2],
  "type": "quick",
  "roms_ids": [],
  "apis": ["igdb", "ss"],
  "launchbox_remote_enabled": true,
  "playmatch_enabled": false
}
```

Response `202` with the task id, so the client can follow the run through the endpoints that already exist:

```json
{ "task_id": "..." }
```

`409` when a scan is already running.
Today that case comes back as `scan:done_ko` with "A scan is already in progress".

Live progress can stay on the socket.
This request is only about kicking a scan off without a session cookie.
