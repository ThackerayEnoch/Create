Advanced Train Dispatch v13

CLIENT_SERVER mode now uses two parallel coroutines:
- networkLoop(): dedicated rednet.receive() listener
- tickLoop(): periodic peripheral/inventory/controller work

This avoids losing rednet_message events while peripheral calls yield.
STANDALONE mode keeps the legacy polling behavior.
