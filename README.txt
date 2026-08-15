Advanced Train Dispatch System - v4

Files:
  install.lua    Client installer / station configuration / server installer
  station.lua    Client demand controller
  server.lua     Supply / central server
  protocol.lua   Broadcast protocol

Wireless broadcast requirements:
  - CC:Tweaked wireless modem peripheral
  - Peripheral name must match modem_<number>, e.g. modem_0, modem_1
  - The modem must report isWireless() == true
  - Wired modems are not used for Rednet broadcast

CLIENT_SERVER discovery:
  1. Installer checks for modem_<number>.
  2. Sends HELLO using protocol ADV_TRAIN_DISPATCH_V1.
  3. Waits 5 seconds for all ANSWER messages using the same protocol.
  4. Displays every discovered server and its normalized resource type.
  5. Only then filters servers matching the requested resource.

Important diagnostics:
  - If no wireless modem exists, the installer explicitly reports that instead of
    incorrectly reporting that no server answered.
  - If a server answers with a different resource, all answers are displayed.
  - The supply server monitor records RX/TX protocol events, including HELLO and
    ANSWER, and keeps the most recent 10 runtime events.

Resource naming:
  Namespace prefixes are removed for station names and broadcast resource keys.
  Example:
      minecraft:iron_block -> iron_block
      iron_block_Request_Factory_A
      WATTING_iron_block_Request_Factory_A
      DISABLE_iron_block_Request_Factory_A
      iron_block_Supply

Startup:
  Client PCs in configured mode start station.lua automatically.
  Installed supply-server PCs start server.lua automatically.
