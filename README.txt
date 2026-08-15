Advanced Train Dispatch v11

Change from v10:
- Supply server still broadcasts ALLOW_RENAME as required.
- Supply server additionally sends the same ALLOW_RENAME payload directly to the requesting client ID.
- Payload still contains no source/destination fields.
- Client logs receipt of protocol-qualified Rednet messages before handling them.
- This makes the server->requesting-client path observable and robust while preserving the broadcast protocol.
