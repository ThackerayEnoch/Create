-- Advanced Train Dispatch protocol.
-- Payloads intentionally contain no source/destination fields.
local M = {}
M.PROTOCOL = "ADV_TRAIN_DISPATCH_V1"
M.REQUEST_RENAME = "REQUEST_RENAME"
M.ALLOW_RENAME = "ALLOW_RENAME"
M.NO_RESOURCE = "NO_RESOURCE"
M.PAUSE = "PAUSE"
M.ENABLE = "ENABLE"
M.HELLO = "HELLO"
M.ANSWER = "ANSWER"
M.HEARTBEAT = "HEARTBEAT"
return M
