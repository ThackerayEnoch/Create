Advanced Train Dispatch v3

Files:
- install.lua   client/server installer and configuration UI
- station.lua   request/client controller
- server.lua    supply/central server
- protocol.lua  broadcast protocol constants

Required for CLIENT_SERVER mode:
- Wireless modem peripheral named modem_<number>, e.g. modem_0
- The modem must report isWireless() == true

Server runtime also requires:
- Create_Station
- configured train storage / portable storage interface
- monitor (monitor or monitor_<number>)

Station resource names use the namespace-free form:
  minecraft:iron_block -> iron_block
