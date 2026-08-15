--[[
    Advanced Train Dispatch - supply/central server.

    One server controls one supply station/resource pair.
    The server requires:
      - Create Train Station
      - Train storage / portable storage interface peripheral
      - Wireless modem named modem_<number>
      - Monitor for runtime status/log display
]]

local CONFIG_PATH = "/server_config.lua"
local PROTOCOL_PATH = "/protocol.lua"
local protocol = dofile(PROTOCOL_PATH)

--------------------------------------------------
-- Basic helpers
--------------------------------------------------

local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function ask(prompt, default)
    if default ~= nil then
        write(prompt .. " [" .. tostring(default) .. "]: ")
    else
        write(prompt .. ": ")
    end
    local value = read()
    if value == "" and default ~= nil then return default end
    return value
end

local function askYesNo(prompt, default)
    while true do
        local value = string.lower(tostring(ask(prompt, default)))
        if value == "y" or value == "yes" then return true end
        if value == "n" or value == "no" then return false end
        print("Please enter y or n.")
    end
end

local function normalizeResourceName(name)
    name = tostring(name or "")
    local _, value = name:match("^([^:]+):(.+)$")
    if value then return value end
    return name
end

local function findWirelessModem()
    for _, name in ipairs(peripheral.getNames()) do
        if name:match("^modem_%d+$") and peripheral.getType(name) == "modem" then
            local modem = peripheral.wrap(name)
            if modem then
                local ok, wireless = pcall(function() return modem.isWireless() end)
                if ok and wireless == true then return name end
            end
        end
    end
    return nil
end

local function findMonitor()
    for _, name in ipairs(peripheral.getNames()) do
        if name == "monitor" or name:match("^monitor_%d+$") then
            if peripheral.getType(name) == "monitor" then
                local monitor = peripheral.wrap(name)
                if monitor then return monitor, name end
            end
        end
    end
    return nil, nil
end

--------------------------------------------------
-- Configuration
--------------------------------------------------

local function saveConfig(config)
    local file = fs.open(CONFIG_PATH, "w")
    if not file then error("Cannot write server_config.lua") end
    file.writeLine("return {")
    file.writeLine("    version = 2,")
    file.writeLine("    stationPeripheral = " .. string.format("%q", config.stationPeripheral) .. ",")
    file.writeLine("    stationName = " .. string.format("%q", config.stationName) .. ",")
    file.writeLine("    factoryId = " .. string.format("%q", config.factoryId) .. ",")
    file.writeLine("    resourceType = " .. string.format("%q", config.resourceType) .. ",")
    file.writeLine("    resourceKind = " .. string.format("%q", config.resourceKind) .. ",")
    file.writeLine("    trainStoragePeripheral = " .. string.format("%q", config.trainStoragePeripheral) .. ",")
    file.writeLine("    containerSize = " .. tostring(tonumber(config.containerSize) or 0))
    file.writeLine("}")
    file.close()
end

local function loadConfig()
    if not fs.exists(CONFIG_PATH) then return nil end
    local ok, config = pcall(dofile, CONFIG_PATH)
    if ok and type(config) == "table" then return config end
    return nil
end

--------------------------------------------------
-- Peripheral selection
--------------------------------------------------

local function scanStations()
    local out = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "Create_Station" then
            local peripheralObject = peripheral.wrap(name)
            if peripheralObject then
                local ok, stationName = pcall(function() return peripheralObject.getStationName() end)
                if ok then
                    table.insert(out, {
                        peripheralName = name,
                        name = tostring(stationName or ""),
                        peripheral = peripheralObject
                    })
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.peripheralName < b.peripheralName end)
    return out
end

local function selectStation()
    while true do
        clearScreen()
        print("=== Supply Station Selection ===")
        print()
        local list = scanStations()
        for i, station in ipairs(list) do
            print("[" .. i .. "] " .. station.peripheralName .. "  " .. station.name)
        end
        if #list == 0 then
            print("No Create_Station found.")
            sleep(2)
        else
            local number = tonumber(ask("Select station"))
            if number and list[number] then return list[number] end
        end
    end
end

local function deviceCapabilities(name)
    local peripheralObject = peripheral.wrap(name)
    if not peripheralObject then return nil end
    local itemOK = pcall(function() peripheralObject.list() end)
    local fluidOK = pcall(function() peripheralObject.tanks() end)
    if itemOK then return "item", peripheralObject end
    if fluidOK then return "fluid", peripheralObject end
    return nil
end

local function scanStorage()
    local out = {}
    for _, name in ipairs(peripheral.getNames()) do
        local kind, peripheralObject = deviceCapabilities(name)
        if kind then
            table.insert(out, {
                peripheralName = name,
                kind = kind,
                peripheral = peripheralObject
            })
        end
    end
    table.sort(out, function(a, b) return a.peripheralName < b.peripheralName end)
    return out
end

local function selectStorage()
    while true do
        clearScreen()
        print("=== Train Storage / Interface Selection ===")
        print()
        print("Select the peripheral exposed by the portable storage interface.")
        print("The train must currently be connected to the interface.")
        print()
        local list = scanStorage()
        for i, entry in ipairs(list) do
            print("[" .. i .. "] " .. entry.peripheralName .. "  type=" .. entry.kind)
        end
        if #list == 0 then
            print("No item/fluid storage peripheral found.")
            sleep(2)
        else
            local number = tonumber(ask("Select train container"))
            if number and list[number] then return list[number] end
        end
    end
end

local function scanResourceNames(storage)
    local result = {}
    local seen = {}
    if storage.kind == "item" then
        local ok, items = pcall(function() return storage.peripheral.list() end)
        if ok and type(items) == "table" then
            for _, item in pairs(items) do
                if item and item.name then
                    local resource = normalizeResourceName(item.name)
                    if not seen[resource] then
                        seen[resource] = true
                        table.insert(result, resource)
                    end
                end
            end
        end
    else
        local ok, tanks = pcall(function() return storage.peripheral.tanks() end)
        if ok and type(tanks) == "table" then
            for _, tank in pairs(tanks) do
                if tank and tank.name then
                    local resource = normalizeResourceName(tank.name)
                    if not seen[resource] then
                        seen[resource] = true
                        table.insert(result, resource)
                    end
                end
            end
        end
    end
    table.sort(result)
    return result
end

local function selectResource(storage)
    local names = scanResourceNames(storage)
    clearScreen()
    print("=== Resource Type ===")
    print()
    print("Namespace prefixes are removed from the station/broadcast name.")
    print("Example: minecraft:iron_block -> iron_block")
    print()

    if #names > 0 then
        for i, name in ipairs(names) do print("[" .. i .. "] " .. name) end
        print("[m] manually enter")
        local choice = ask("Select resource", "m")
        if choice ~= "m" then
            local number = tonumber(choice)
            if number and names[number] then return normalizeResourceName(names[number]) end
        end
    end

    while true do
        local value = normalizeResourceName(ask("Resource type"))
        if value ~= "" then return value end
    end
end

local function createServerStartup()
    local file = fs.open("/startup.lua", "w")
    if not file then error("Unable to create startup.lua") end
    file.writeLine('shell.run("server.lua")')
    file.close()
end

local function installServer()
    local station = selectStation()
    local storage = selectStorage()
    local resource = selectResource(storage)
    local containerSize = 0
    local sizeOk, size = pcall(function() return storage.peripheral.size() end)
    if sizeOk and tonumber(size) then
        containerSize = tonumber(size)
    end

    clearScreen()
    print("=== Supply Server Setup ===")
    print()
    local factoryId = ask("Factory identifier", "Factory")
    local containerSize = tonumber(ask("Train container size", tostring(containerSize > 0 and containerSize or 0)))
    if not containerSize or containerSize <= 0 then
        containerSize = 0
        print("Container size must be a positive number; using detected value if available.")
    end
    local requestName = resource .. "_Request_" .. factoryId
    local supplyName = resource .. "_Supply"
    print()
    print("Request name: " .. requestName)
    print("Supply name:  " .. supplyName)
    print("Container size: " .. tostring(containerSize))
    print()

    if not askYesNo("Write server configuration?", "y") then return end

    saveConfig({
        stationPeripheral = station.peripheralName,
        stationName = station.name,
        factoryId = factoryId,
        resourceType = resource,
        resourceKind = storage.kind,
        trainStoragePeripheral = storage.peripheralName,
        containerSize = containerSize
    })

    if fs.exists("/disk/server.lua") then
        fs.delete("/server.lua")
        fs.copy("/disk/server.lua", "/server.lua")
    end
    if fs.exists("/disk/protocol.lua") then
        fs.delete("/protocol.lua")
        fs.copy("/disk/protocol.lua", "/protocol.lua")
    end

    createServerStartup()
    print("Server installed and startup.lua configured for server.lua.")
    print("Keep the portable storage interface connected to the computer network.")
end

--------------------------------------------------
-- Self-check
--------------------------------------------------

local config = loadConfig()

local function selfCheck()
    local problems = {}

    if not config then table.insert(problems, "server_config.lua missing or invalid") end
    if not fs.exists(PROTOCOL_PATH) then table.insert(problems, "protocol.lua missing") end

    local modemName = findWirelessModem()
    if not modemName then
        table.insert(problems, "wireless modem_x not found; required pattern: modem_<number>")
    end

    local monitor, monitorName = findMonitor()
    if not monitor then table.insert(problems, "monitor not found") end

    local station = config and peripheral.wrap(config.stationPeripheral) or nil
    if not station then
        table.insert(problems, "supply Create_Station not found")
    end

    local storage = config and peripheral.wrap(config.trainStoragePeripheral) or nil
    if not storage then
        table.insert(problems, "train storage peripheral not found")
    elseif config.resourceKind == "item" then
        local ok = pcall(function() storage.list() end)
        if not ok then table.insert(problems, "configured train storage does not support list()") end
    elseif config.resourceKind == "fluid" then
        local ok = pcall(function() storage.tanks() end)
        if not ok then table.insert(problems, "configured train storage does not support tanks()") end
    end

    if config and tostring(config.resourceType or "") == "" then
        table.insert(problems, "resourceType is empty")
    end

    if #problems > 0 then
        clearScreen()
        print("SUPPLY SERVER SELF-CHECK FAILED")
        print()
        for _, problem in ipairs(problems) do print("- " .. problem) end
        error("Supply server self-check failed")
    end

    return modemName, monitor, monitorName, station, storage
end

local args = {...}
if args[1] == "install" or not config then
    installServer()
    config = loadConfig()
end

if not config then error("No server configuration") end

local modemName, monitor, monitorName, station, storage = selfCheck()

if not rednet.isOpen(modemName) then rednet.open(modemName) end

--------------------------------------------------
-- Runtime state / logging
--------------------------------------------------

local requestName = normalizeResourceName(config.resourceType) .. "_Request_" .. config.factoryId
local supplyName = normalizeResourceName(config.resourceType) .. "_Supply"
local resourceType = normalizeResourceName(config.resourceType)
local paused = false
local noResource = false
local noRequestSince = os.clock()
local lastResourceCheck = 0
local logs = {}
local MAX_LOGS = 15
local currentStatus = "STARTING"

local function now()
    return os.date("%H:%M:%S")
end

local function addLog(message)
    table.insert(logs, 1, "[" .. now() .. "] " .. tostring(message))
    while #logs > MAX_LOGS do table.remove(logs) end
    print(logs[1])
end

local function setStatus(status)
    currentStatus = status
end

local function stationSetName(name)
    local ok, err = pcall(function() station.setStationName(name) end)
    if ok then return true end
    addLog("ERROR rename " .. tostring(name) .. ": " .. tostring(err))
    setStatus("ERROR")
    return false
end

local function drawMonitor()
    if not monitor then return end
    local width, height = monitor.getSize()
    monitor.setTextScale(0.5)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()

    local function line(y, text, color)
        if y < 1 or y > height then return end
        monitor.setTextColor(color or colors.white)
        monitor.setCursorPos(1, y)
        monitor.write(string.sub(tostring(text), 1, width))
    end

    local mode = "AVAILABLE"
    if noResource then
        mode = "NO RESOURCE"
    elseif paused then
        mode = "PAUSED"
    elseif os.clock() - noRequestSince >= 60 then
        mode = "NO REQUEST"
    end

    line(1, "ADVANCED TRAIN SUPPLY SERVER", colors.cyan)
    line(2, "Resource: " .. resourceType, colors.white)
    line(3, "Station:  " .. requestName, colors.white)
    line(4, "Status:   " .. mode, noResource and colors.red or (paused and colors.orange or colors.lime))
    line(5, "Modem:    " .. modemName, colors.lightBlue)
    line(6, "Monitor:  " .. monitorName, colors.lightBlue)
    line(7, "Last 15 runtime events:", colors.yellow)

    local maxVisible = math.max(1, height - 7)
    for i = 1, math.min(#logs, maxVisible) do
        line(7 + i, logs[i], colors.white)
    end
end

local function broadcast(messageType)
    local message = {
        protocol = protocol.PROTOCOL,
        type = messageType,
        resourceType = resourceType
    }
    local ok, err = pcall(function()
        rednet.broadcast(message, protocol.PROTOCOL)
    end)
    if ok then
        addLog("TX BROADCAST " .. tostring(messageType) .. " [" .. resourceType .. "]")
        return true
    end
    addLog("ERROR TX BROADCAST " .. tostring(messageType) .. ": " .. tostring(err))
    setStatus("ERROR")
    return false
end

local function sendAnswer(sender)
    local message = {
        protocol = protocol.PROTOCOL,
        type = protocol.ANSWER,
        resourceType = resourceType
    }
    local ok = pcall(function()
        rednet.send(sender, message, protocol.PROTOCOL)
    end)
    if ok then
        addLog("TX ANSWER -> #" .. tostring(sender) .. " [" .. resourceType .. "]")
        return true
    end
    addLog("ERROR TX ANSWER -> #" .. tostring(sender))
    setStatus("ERROR")
    return false
end

local function isFull()
    if not storage then return false end

    if config.resourceKind == "fluid" then
        local ok, tanks = pcall(function() return storage.tanks() end)
        if not ok or type(tanks) ~= "table" then return false end

        local totalCapacity = 0
        local totalAmount = 0
        for _, tank in pairs(tanks) do
            if tank then
                totalCapacity = totalCapacity + (tonumber(tank.capacity) or 0)
                if normalizeResourceName(tank.name) == resourceType then
                    totalAmount = totalAmount + (tonumber(tank.amount) or 0)
                end
            end
        end
        return totalCapacity > 0 and totalAmount >= totalCapacity
    end

    local savedSize = tonumber(config.containerSize) or 0
    local okSize, size = pcall(function() return storage.size() end)
    local sizeLimit = 0
    if savedSize and savedSize > 0 then
        sizeLimit = savedSize
    elseif okSize and size and size > 0 then
        sizeLimit = size
    end
    if sizeLimit <= 0 then return false end

    local okList, items = pcall(function() return storage.list() end)
    if not okList or type(items) ~= "table" then return false end

    local resourceCount = 0
    for _, item in pairs(items) do
        if item and normalizeResourceName(item.name) == resourceType then
            resourceCount = resourceCount + (tonumber(item.count) or 0)
        end
    end

    return resourceCount >= sizeLimit and resourceCount > 0
end

local function runInitialState()
    if isFull() then
        noResource = false
        paused = false
        stationSetName(supplyName)
        setStatus("AVAILABLE")
    else
        stationSetName(requestName)
        setStatus("WAITING")
    end
end

runInitialState()
addLog("STARTUP OK | resource=" .. resourceType .. " modem=" .. modemName)
addLog("STATUS " .. currentStatus .. " | station=" .. requestName)
drawMonitor()

--------------------------------------------------
-- Main event loop
--------------------------------------------------

while true do
    local sender, message = rednet.receive(protocol.PROTOCOL, 1)

    if type(message) == "table" then
        local messageType = tostring(message.type or "UNKNOWN")
        local messageResource = message.resourceType and normalizeResourceName(message.resourceType) or nil
        addLog("RX #" .. tostring(sender) .. " " .. messageType ..
            (messageResource and (" [" .. messageResource .. "]") or "") ..
            " protocol=" .. tostring(message.protocol))

        if messageType == protocol.HELLO then
            sendAnswer(sender)

        elseif messageType == protocol.HEARTBEAT and messageResource == resourceType then
            noRequestSince = os.clock()
            addLog("RX HEARTBEAT -> #" .. tostring(sender) .. " [" .. resourceType .. "]")

        elseif messageResource == resourceType and messageType == protocol.REQUEST_RENAME then
            noRequestSince = os.clock()

            if noResource then
                paused = true
                setStatus("NO RESOURCE")
                broadcast(protocol.PAUSE)
                stationSetName(requestName)
            else
                paused = false
                setStatus("AVAILABLE")
                -- Keep the required broadcast, and additionally reply directly to
                -- the requesting client. The payload remains source/destination-free.
                broadcast(protocol.ALLOW_RENAME)
                local allowMessage = {
                    protocol = protocol.PROTOCOL,
                    type = protocol.ALLOW_RENAME,
                    resourceType = resourceType
                }
                local directOk, directResultOrErr = pcall(function()
                    return rednet.send(sender, allowMessage, protocol.PROTOCOL)
                end)
                if directOk then
                    addLog("TX DIRECT ALLOW_RENAME -> #" .. tostring(sender) .. " [" .. resourceType .. "] result=" .. tostring(directResultOrErr))
                else
                    addLog("ERROR TX DIRECT ALLOW_RENAME -> #" .. tostring(sender) .. ": " .. tostring(directResultOrErr))
                end
                stationSetName(supplyName)
            end

        elseif messageResource == resourceType and messageType == protocol.NO_RESOURCE then
            noResource = true
            paused = true
            setStatus("NO RESOURCE")
            broadcast(protocol.PAUSE)
            stationSetName(requestName)
        end
    end

    if isFull() then
        if noResource or paused or currentStatus ~= "AVAILABLE" then
            noResource = false
            paused = false
            stationSetName(supplyName)
            setStatus("AVAILABLE")
            broadcast(protocol.ENABLE)
        end
    end

    if noResource and os.clock() - lastResourceCheck >= 5 then
        lastResourceCheck = os.clock()
        if isFull() then
            noResource = false
            paused = false
            stationSetName(supplyName)
            setStatus("AVAILABLE")
            broadcast(protocol.ENABLE)
            addLog("RECOVER ENABLE | resourceCount >= containerSize")
        end
    end

    if os.clock() - noRequestSince >= 60 then
        if currentStatus ~= "NO REQUEST" then
            stationSetName(requestName)
            setStatus("NO REQUEST")
            addLog("TIMEOUT 60s -> " .. requestName)
        end
    end

    drawMonitor()
end
