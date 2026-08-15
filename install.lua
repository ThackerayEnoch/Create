--[[
    Create Factory Train Station Controller
    Multi-station Installation / Update Program

    One Computer controls multiple request stations in one factory.
    Each station has its own:
      - Train Station
      - Inventory peripheral
      - Requested item
      - Capacity
      - Enable / disable thresholds

    Startup menu:
      1. Run controller
      2. Install / replace all stations
      3. Update one station
      4. Add one station
      5. Delete one station
      6. Install advanced supply server
      7. Exit
]]

local CONFIG_PATH = "/config.lua"
local INSTALL_PATH = "/install.lua"
local STATION_PROGRAM_PATH = "/station.lua"
local SERVER_PROGRAM_PATH = "/server.lua"
local PROTOCOL_PATH = "/protocol.lua"

--------------------------------------------------
-- Basic utilities
--------------------------------------------------

local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function pause()
    print()
    print("Press ENTER to continue...")
    read()
end

local function ask(prompt, default)
    if default ~= nil then
        write(prompt .. " [" .. tostring(default) .. "]: ")
    else
        write(prompt .. ": ")
    end

    local value = read()

    if value == "" and default ~= nil then
        return default
    end

    return value
end

local function askNumber(prompt, default, min, max)
    while true do
        local value = ask(prompt, default)
        local number = tonumber(value)

        if number
            and (min == nil or number >= min)
            and (max == nil or number <= max) then
            return number
        end

        print("Invalid number, please try again.")
    end
end

local function askYesNo(prompt, default)
    while true do
        local value = string.lower(tostring(ask(prompt, default)))

        if value == "y" or value == "yes" then
            return true
        end

        if value == "n" or value == "no" then
            return false
        end

        print("Please enter y or n.")
    end
end

local function normalizeResourceName(name)
    name = tostring(name or "")
    local prefix, value = name:match("^([^:]+):(.+)$")
    if prefix and value then
        return value
    end
    return name
end

local function findWirelessModem()
    for _, name in ipairs(peripheral.getNames()) do
        if name:match("^modem_%d+$") and peripheral.getType(name) == "modem" then
            local modem = peripheral.wrap(name)
            if modem then
                local ok, wireless = pcall(function() return modem.isWireless() end)
                if ok and wireless == true then
                    return name
                end
            end
        end
    end
    return nil
end

local function safeReadFile(path)
    if not fs.exists(path) then
        return nil
    end

    local file = fs.open(path, "r")
    if not file then
        return nil
    end

    local content = file.readAll()
    file.close()
    return content
end

--------------------------------------------------
-- Config loading
--------------------------------------------------

local function loadConfig()
    if not fs.exists(CONFIG_PATH) then
        return nil
    end

    local ok, result = pcall(dofile, CONFIG_PATH)

    if not ok or type(result) ~= "table" then
        print("ERROR: config.lua is invalid.")
        print(tostring(result))
        return nil
    end

    if type(result.stations) ~= "table" then
        result.stations = {}
    end

    return result
end

--------------------------------------------------
-- Write config.lua
--------------------------------------------------

local function luaString(value)
    return string.format("%q", tostring(value or ""))
end

local function writeConfig(config)
    local file = fs.open(CONFIG_PATH, "w")
    if not file then
        error("Unable to create config.lua")
    end

    file.writeLine("return {")
    file.writeLine("    version = 2,")
    file.writeLine("    checkInterval = " .. tostring(config.checkInterval or 5) .. ",")
    file.writeLine("    stations = {")

    for i, station in ipairs(config.stations) do
        file.writeLine("        {")
        file.writeLine("            id = " .. luaString(station.id) .. ",")
        file.writeLine("            physicalStation = " .. luaString(station.physicalStation) .. ",")
        file.writeLine("            stationName = " .. luaString(station.stationName) .. ",")
        file.writeLine("            disabledName = " .. luaString(station.disabledName) .. ",")
        file.writeLine("            inventoryPeripheral = " .. luaString(station.inventoryPeripheral) .. ",")
        file.writeLine("            inventoryType = " .. luaString(station.inventoryType) .. ",")
        file.writeLine("            item = " .. luaString(station.item) .. ",")
        file.writeLine("            capacity = " .. tostring(station.capacity) .. ",")
        file.writeLine("            enablePercent = " .. tostring(station.enablePercent) .. ",")
        file.writeLine("            disablePercent = " .. tostring(station.disablePercent) .. ",")
        file.writeLine("            advanced = " .. tostring(station.advanced == true) .. ",")
        file.writeLine("            resourceType = " .. luaString(station.resourceType or station.item) .. ",")
        file.writeLine("            resourceKind = " .. luaString(station.resourceKind or "item") .. ",")
        file.writeLine("            factoryId = " .. luaString(station.factoryId or station.id) .. ",")
        file.writeLine("            requestName = " .. luaString(station.requestName or station.stationName) .. ",")
        file.writeLine("            waitingName = " .. luaString(station.waitingName or ("WATTING_" .. (station.requestName or station.stationName))) .. ",")
        file.writeLine("            advancedDisabledName = " .. luaString(station.advancedDisabledName or ("DISABLE_" .. (station.requestName or station.stationName))) .. ",")
        file.writeLine("            supplyName = " .. luaString(station.supplyName or ((station.resourceType or station.item) .. "_Supply")) .. ",")
        file.writeLine("            serverId = " .. tostring(tonumber(station.serverId) or 0) .. ",")
        file.writeLine("            trainStoragePeripheral = " .. luaString(station.trainStoragePeripheral or ""))
        file.writeLine("        }" .. (i < #config.stations and "," or ""))
    end

    file.writeLine("    }")
    file.writeLine("}")
    file.close()
end

--------------------------------------------------
-- Create Station scanning
--------------------------------------------------

local function scanStations()
    local stations = {}

    for _, peripheralName in ipairs(peripheral.getNames()) do
        if peripheral.getType(peripheralName) == "Create_Station" then
            local station = peripheral.wrap(peripheralName)

            if station then
                local ok, stationName = pcall(function()
                    return station.getStationName()
                end)

                if ok then
                    table.insert(stations, {
                        peripheralName = peripheralName,
                        stationName = tostring(stationName or ""),
                        peripheral = station
                    })
                end
            end
        end
    end

    table.sort(stations, function(a, b)
        return a.peripheralName < b.peripheralName
    end)

    return stations
end

local function selectStation(excludePeripheralName)
    while true do
        local stations = scanStations()

        clearScreen()
        print("========================================")
        print("        Train Station Selection")
        print("========================================")
        print()

        local visible = {}

        for _, station in ipairs(stations) do
            if station.peripheralName ~= excludePeripheralName then
                table.insert(visible, station)
            end
        end

        if #visible == 0 then
            print("No selectable Create Train Station found.")
            print()
            print("Check the Wired Modem connection.")
            pause()
        else
            for i, station in ipairs(visible) do
                print("[" .. i .. "] " .. station.peripheralName)
                print("    Current name: " .. station.stationName)
                print()
            end

            local choice = tonumber(ask("Select station"))
            if choice and visible[choice] then
                return visible[choice]
            end

            print("Invalid selection.")
            sleep(1)
        end
    end
end

local function stationNameUsed(config, name, excludedIndex)
    for i, station in ipairs(config.stations or {}) do
        if i ~= excludedIndex then
            if station.stationName == name or station.disabledName == name
                or station.requestName == name or station.waitingName == name
                or station.advancedDisabledName == name or station.supplyName == name then
                return true, station
            end
        end
    end

    return false, nil
end

local function configureStationName(config, selectedStation, existingIndex)
    while true do
        clearScreen()
        print("========================================")
        print("          Station Name Setup")
        print("========================================")
        print()
        print("Physical device: " .. selectedStation.peripheralName)
        print("Current name:    " .. selectedStation.stationName)
        print()

        local defaultName = existingIndex and config.stations[existingIndex].stationName or ""
        local stationName = ask("Official station name", defaultName)

        if stationName == "" then
            print("Station name cannot be empty.")
            pause()
        else
            local used, conflict = stationNameUsed(config, stationName, existingIndex)
            if used then
                print("Name conflict with: " .. tostring(conflict.stationName))
                pause()
            else
                local defaultDisabled = existingIndex
                    and config.stations[existingIndex].disabledName
                    or ("DISABLED_" .. stationName)

                local disabledName = ask("Disabled station name", defaultDisabled)

                if disabledName == "" or disabledName == stationName then
                    print("Disabled name must be non-empty and different from the normal name.")
                    pause()
                else
                    local disabledUsed, disabledConflict = stationNameUsed(
                        config,
                        disabledName,
                        existingIndex
                    )

                    if disabledUsed then
                        print("Disabled name conflicts with: " .. tostring(disabledConflict.stationName))
                        pause()
                    else
                        return stationName, disabledName
                    end
                end
            end
        end
    end
end

--------------------------------------------------
-- Inventory scanning
--------------------------------------------------

local function getInventoryInfo(peripheralName)
    local device = peripheral.wrap(peripheralName)
    if not device then
        return nil
    end

    local ok, items = pcall(function()
        return device.list()
    end)

    if not ok or type(items) ~= "table" then
        return nil
    end

    return {
        peripheralName = peripheralName,
        peripheralType = peripheral.getType(peripheralName),
        peripheral = device,
        items = items
    }
end

local function scanInventories()
    local inventories = {}

    for _, peripheralName in ipairs(peripheral.getNames()) do
        local info = getInventoryInfo(peripheralName)
        if info then
            table.insert(inventories, info)
        end
    end

    table.sort(inventories, function(a, b)
        return a.peripheralName < b.peripheralName
    end)

    return inventories
end

local function selectInventory(excludedPeripheralName)
    while true do
        local inventories = scanInventories()

        clearScreen()
        print("========================================")
        print("          Inventory Selection")
        print("========================================")
        print()

        local visible = {}
        for _, inventory in ipairs(inventories) do
            if inventory.peripheralName ~= excludedPeripheralName then
                table.insert(visible, inventory)
            end
        end

        if #visible == 0 then
            print("No readable inventory device found.")
            print("The device must support inventory.list().")
            pause()
        else
            for i, inventory in ipairs(visible) do
                local slotCount = 0
                for _ in pairs(inventory.items) do
                    slotCount = slotCount + 1
                end

                print("[" .. i .. "] " .. inventory.peripheralName)
                print("    Type: " .. tostring(inventory.peripheralType))
                print("    Used slots: " .. tostring(slotCount))
                print()
            end

            local choice = tonumber(ask("Select inventory"))
            if choice and visible[choice] then
                return visible[choice]
            end

            print("Invalid selection.")
            sleep(1)
        end
    end
end

--------------------------------------------------
-- Item selection from inventory
--------------------------------------------------

local function buildItemList(inventory)
    local aggregated = {}

    for _, item in pairs(inventory.items) do
        if item and item.name then
            if not aggregated[item.name] then
                aggregated[item.name] = 0
            end

            aggregated[item.name] = aggregated[item.name] + (item.count or 0)
        end
    end

    local result = {}

    for name, count in pairs(aggregated) do
        table.insert(result, {
            name = name,
            count = count
        })
    end

    table.sort(result, function(a, b)
        return a.name < b.name
    end)

    return result
end

local function selectItem(inventory)
    local items = buildItemList(inventory)

    if #items == 0 then
        print()
        print("The selected inventory is empty.")
        print("Please put at least one item into it, then rescan.")
        pause()
        return nil
    end

    local pageSize = 20
    local page = 1
    local totalPages = math.ceil(#items / pageSize)

    while true do
        clearScreen()
        print("========================================")
        print("       Requested Item Selection")
        print("========================================")
        print()
        print("Inventory: " .. inventory.peripheralName)
        print("Items found: " .. tostring(#items))
        print("Page " .. tostring(page) .. "/" .. tostring(totalPages))
        print()

        local startIndex = (page - 1) * pageSize + 1
        local endIndex = math.min(startIndex + pageSize - 1, #items)

        for i = startIndex, endIndex do
            local item = items[i]
            print(
                "[" .. (i - startIndex + 1) .. "] "
                .. item.name
                .. " x"
                .. tostring(item.count)
            )
        end

        print()
        print("[n] next page   [p] previous page   [q] cancel")

        local input = string.lower(ask("Select item"))

        if input == "q" then
            return nil
        elseif input == "n" and page < totalPages then
            page = page + 1
        elseif input == "p" and page > 1 then
            page = page - 1
        else
            local choice = tonumber(input)
            if choice and choice >= 1 and choice <= (endIndex - startIndex + 1) then
                return items[startIndex + choice - 1].name
            end

            print("Invalid selection.")
            sleep(1)
        end
    end
end

--------------------------------------------------
-- Advanced CLIENT_SERVER setup helpers
--------------------------------------------------

local function loadProtocol()
    if not fs.exists("/disk/protocol.lua") then
        error("protocol.lua is missing from the floppy disk.")
    end
    return dofile("/disk/protocol.lua")
end

local function openRednetForInstall()
    local modem = findWirelessModem()
    if not modem then
        return nil, "Wireless modem not found. Required device name: modem_<number>."
    end

    local ok, err = pcall(function()
        if not rednet.isOpen(modem) then
            rednet.open(modem)
        end
    end)

    if not ok then
        return nil, "Failed to open wireless modem " .. modem .. ": " .. tostring(err)
    end

    return modem, nil
end

local function discoverServersForResource(resourceType)
    local protocol = loadProtocol()
    resourceType = normalizeResourceName(resourceType)

    local modem, modemError = openRednetForInstall()
    if not modem then
        return nil, nil, modemError
    end

    clearScreen()
    print("========================================")
    print("        Center Server Discovery")
    print("========================================")
    print()
    print("Wireless modem: " .. modem)
    print("Protocol:        " .. protocol.PROTOCOL)
    print("Resource filter: " .. resourceType)
    print()

    local message = {
        protocol = protocol.PROTOCOL,
        type = protocol.HELLO
    }

    local sent, sendError = pcall(function()
        rednet.broadcast(message, protocol.PROTOCOL)
    end)

    if not sent then
        return nil, nil, "HELLO broadcast failed on " .. modem .. ": " .. tostring(sendError)
    end

    print("HELLO sent. Waiting 5 seconds for ANSWER...")
    print()

    local deadline = os.clock() + 5
    local allAnswers = {}
    local matching = {}
    local seen = {}
    local answerCount = 0

    while os.clock() < deadline do
        local timeout = math.max(0.05, deadline - os.clock())
        local sender, received = rednet.receive(protocol.PROTOCOL, timeout)
        if not sender then
            break
        end

        if type(received) == "table" and received.type == protocol.ANSWER then
            local receivedResource = normalizeResourceName(received.resourceType)
            answerCount = answerCount + 1

            if not seen[sender] then
                seen[sender] = true
                table.insert(allAnswers, {
                    id = sender,
                    resourceType = receivedResource
                })

                if receivedResource == resourceType then
                    table.insert(matching, sender)
                end
            end
        end
    end

    table.sort(allAnswers, function(a, b)
        return tonumber(a.id) < tonumber(b.id)
    end)
    table.sort(matching, function(a, b)
        return tonumber(a) < tonumber(b)
    end)

    return matching, allAnswers, nil
end

local function selectServerForResource(resourceType)
    local servers, allAnswers, discoveryError = discoverServersForResource(resourceType)

    clearScreen()
    print("========================================")
    print("        Center Server Selection")
    print("========================================")
    print()
    print("Resource: " .. normalizeResourceName(resourceType))
    print()

    if discoveryError then
        print("DISCOVERY FAILED")
        print()
        print(discoveryError)
        print()
        print("Required wireless modem name: modem_<number>")
        print("The modem must report isWireless() == true.")
        pause()
        return nil
    end

    print("ANSWER received:")
    if not allAnswers or #allAnswers == 0 then
        print("  <none>")
    else
        for _, answer in ipairs(allAnswers) do
            print("  Computer ID " .. tostring(answer.id) .. " -> " .. tostring(answer.resourceType))
        end
    end

    print()
    if not servers or #servers == 0 then
        print("No matching center server answered HELLO.")
        print()
        if allAnswers and #allAnswers > 0 then
            print("A server answered, but its resource type did not match.")
            print("Check the Resource type on both sides.")
        else
            print("No ANSWER was received at all.")
            print("Check that the center server is running and has wireless modem_x.")
        end
        print()
        print("The center server display should show:")
        print("  RX #<client> HELLO")
        print("  TX ANSWER -> #<client>")
        pause()
        return nil
    end

    print("Matching servers:")
    for i, id in ipairs(servers) do
        print("[" .. i .. "] Computer ID " .. id)
    end

    while true do
        local n = tonumber(ask("Select center server", 1))
        if n and servers[n] then
            return servers[n]
        end
        print("Invalid selection.")
    end
end

local function storageSupportsItems(p)
    return pcall(function() return p.list() end)
end

local function storageSupportsFluids(p)
    return pcall(function() return p.tanks() end)
end

local function scanTrainStorages()
    local result={}
    for _, name in ipairs(peripheral.getNames()) do
        local p=peripheral.wrap(name)
        if p then
            local itemOK=storageSupportsItems(p)
            local fluidOK=storageSupportsFluids(p)
            if itemOK or fluidOK then
                table.insert(result,{peripheralName=name, peripheral=p, kind=itemOK and "item" or "fluid"})
            end
        end
    end
    table.sort(result,function(a,b) return a.peripheralName<b.peripheralName end)
    return result
end

local function selectTrainStorage(resourceKind)
    while true do
        clearScreen()
        print("========================================")
        print("          Train Container Selection")
        print("========================================")
        print()
        print("Select the peripheral exposed by the portable storage interface.")
        print("The train must currently be connected to the interface.")
        print()
        local list=scanTrainStorages()
        local visible={}
        for _,x in ipairs(list) do
            if not resourceKind or x.kind==resourceKind then table.insert(visible,x) end
        end
        for i,x in ipairs(visible) do print("["..i.."] "..x.peripheralName.."  type="..x.kind) end
        if #visible==0 then
            print("No matching item/fluid storage peripheral found.")
            print("For fluids, ensure the portable interface exposes tanks().")
            pause()
        else
            local n=tonumber(ask("Select train container"))
            if n and visible[n] then return visible[n] end
        end
    end
end

local function configureAdvancedStations(config)
    clearScreen()
    print("========================================")
    print("       CLIENT_SERVER Configuration")
    print("========================================")
    print()
    print("The installer will discover all center servers with HELLO/ANSWER,")
    print("then bind a currently connected train container for each station.")
    print()

    for i, station in ipairs(config.stations) do
        clearScreen()
        print("Station "..i.."/"..#config.stations)
        print("Station: "..station.stationName)
        print("Item:    "..station.item)
        print()
        local resourceType=normalizeResourceName(ask("Resource type",station.item))
        local resourceKind=ask("Resource kind (item/fluid)","item")
        if resourceKind~="item" and resourceKind~="fluid" then resourceKind="item" end
        local factoryId=ask("Factory identifier",station.id)
        local requestName=resourceType.."_Request_"..factoryId
        local waitingName="WATTING_"..requestName
        local disabledName="DISABLE_"..requestName
        local supplyName=resourceType.."_Supply"
        local serverId=selectServerForResource(resourceType)
        if not serverId then return false end
        local trainStorage=selectTrainStorage(resourceKind)

        station.advanced=true
        station.resourceType=resourceType
        station.resourceKind=resourceKind
        station.factoryId=factoryId
        station.requestName=requestName
        station.waitingName=waitingName
        station.advancedDisabledName=disabledName
        station.supplyName=supplyName
        station.serverId=serverId
        station.trainStoragePeripheral=trainStorage.peripheralName
        station.stationName=requestName
        station.disabledName=disabledName

        local physical=peripheral.wrap(station.physicalStation)
        if physical then
            pcall(function() physical.setStationName(requestName) end)
        end
    end
    config.advancedNetwork=true
    config.networkMode="CLIENT_SERVER"
    return true
end

--------------------------------------------------
-- Station capacity / thresholds
--------------------------------------------------

local function configureStationSettings(existing)
    local defaultCapacity = existing and existing.capacity or 4096
    local defaultEnable = existing and existing.enablePercent or 20
    local defaultDisable = existing and existing.disablePercent or 80

    local capacity = askNumber(
        "Inventory capacity (item count)",
        defaultCapacity,
        1
    )

    local enablePercent = askNumber(
        "Allow entry below (%)",
        defaultEnable,
        0,
        100
    )

    local disablePercent = askNumber(
        "Block entry at/above (%)",
        defaultDisable,
        0,
        100
    )

    if enablePercent >= disablePercent then
        print("Enable threshold must be lower than disable threshold.")
        return nil
    end

    return {
        capacity = capacity,
        enablePercent = enablePercent,
        disablePercent = disablePercent
    }
end

--------------------------------------------------
-- Bind one station
--------------------------------------------------

local function bindStation(config, existingIndex)
    local existing = existingIndex and config.stations[existingIndex] or nil

    local selectedStation = selectStation(nil)
    local stationName, disabledName = configureStationName(config, selectedStation, existingIndex)

    -- Do not allow the same physical station to be assigned twice.
    for i, station in ipairs(config.stations) do
        if i ~= existingIndex and station.physicalStation == selectedStation.peripheralName then
            print("That physical station is already bound to another configuration entry.")
            pause()
            return nil
        end
    end

    local oldInventory = existing and existing.inventoryPeripheral or nil
    local selectedInventory = selectInventory(nil)

    if not selectedInventory then
        return nil
    end

    -- Do not allow the same inventory to be assigned to two stations.
    for i, station in ipairs(config.stations) do
        if i ~= existingIndex and station.inventoryPeripheral == selectedInventory.peripheralName then
            print("That inventory is already bound to another station.")
            pause()
            return nil
        end
    end

    local selectedItem = selectItem(selectedInventory)
    if not selectedItem then
        return nil
    end

    local defaults = existing
        and {
            capacity = existing.capacity,
            enablePercent = existing.enablePercent,
            disablePercent = existing.disablePercent
        }
        or nil

    local settings = configureStationSettings(defaults)
    if not settings then
        pause()
        return nil
    end

    local entry = {
        id = existing and existing.id or ("station_" .. tostring(#config.stations + 1)),
        physicalStation = selectedStation.peripheralName,
        stationName = stationName,
        disabledName = disabledName,
        inventoryPeripheral = selectedInventory.peripheralName,
        inventoryType = selectedInventory.peripheralType,
        item = selectedItem,
        capacity = settings.capacity,
        enablePercent = settings.enablePercent,
        disablePercent = settings.disablePercent
    }

    return entry
end

--------------------------------------------------
-- Startup helpers
--------------------------------------------------

local function createClientStartup()
    local file = fs.open("/startup.lua", "w")
    if not file then
        error("Unable to create startup.lua")
    end

    file.writeLine('if fs.exists("config.lua") and fs.exists("station.lua") then')
    file.writeLine('    shell.run("station.lua")')
    file.writeLine('else')
    file.writeLine('    shell.run("install.lua")')
    file.writeLine('end')
    file.close()
end

local function createServerStartup()
    local file = fs.open("/startup.lua", "w")
    if not file then
        error("Unable to create startup.lua")
    end

    file.writeLine('shell.run("server.lua")')
    file.close()
end

local function createStartup()
    createClientStartup()
end

--------------------------------------------------
-- Install station program from disk
--------------------------------------------------

local function installStationProgram()
    if not fs.exists("/disk/station.lua") then
        error("station.lua is missing from the floppy disk.")
    end

    fs.delete(STATION_PROGRAM_PATH)
    fs.copy("/disk/station.lua", STATION_PROGRAM_PATH)
    if fs.exists("/disk/protocol.lua") then
        fs.delete(PROTOCOL_PATH)
        fs.copy("/disk/protocol.lua", PROTOCOL_PATH)
    end
end

local function installInstallerProgram()
    if not fs.exists("/disk/install.lua") then
        return
    end

    fs.delete(INSTALL_PATH)
    fs.copy("/disk/install.lua", INSTALL_PATH)
end

local function installServerProgram()
    if not fs.exists("/disk/server.lua") then
        error("server.lua is missing from the floppy disk.")
    end
    fs.delete(SERVER_PROGRAM_PATH)
    fs.copy("/disk/server.lua", SERVER_PROGRAM_PATH)
    if fs.exists("/disk/protocol.lua") then
        fs.delete(PROTOCOL_PATH)
        fs.copy("/disk/protocol.lua", PROTOCOL_PATH)
    end
    createServerStartup()
end

--------------------------------------------------
-- Timed startup menu choice
-- If there is no input within timeout seconds,
-- default to Run Controller.
--------------------------------------------------

local function timedMenuChoice(timeout)
    local timer = os.startTimer(timeout)
    local result = nil
    local timedOut = false

    local function inputTask()
        result = read()
    end

    local function timerTask()
        while true do
            local event, id = os.pullEvent()
            if event == "timer" and id == timer then
                timedOut = true
                return
            end
        end
    end

    parallel.waitForAny(inputTask, timerTask)

    if timedOut then
        return nil, true
    end

    return result, false
end

local function showStartupMenu(config)
    clearScreen()
    print("========================================")
    print("       Factory Request Controller")
    print("========================================")
    print()

    if config then
        print("Configured stations: " .. tostring(#config.stations))
    else
        print("No configuration found.")
    end

    print()
    print("[1] Run controller")
    print("[2] Install / replace all stations")
    print("[3] Update one station")
    print("[4] Add one station")
    print("[5] Delete one station")
    print("[6] Install advanced supply server")
    print("[7] Exit")
    print()
    print("Default: Run controller in 5 seconds")
    write("Select mode: ")
end

--------------------------------------------------
-- Show configuration
--------------------------------------------------

local function showConfig(config)
    clearScreen()
    print("========================================")
    print("       Factory Request Controller")
    print("========================================")
    print()
    print("Stations: " .. tostring(#config.stations))
    print()

    for i, station in ipairs(config.stations) do
        print(
            "[" .. i .. "] "
            .. station.stationName
        )
        print(
            "    Item: "
            .. station.item
        )
        print(
            "    Inventory: "
            .. station.inventoryPeripheral
        )
        print(
            "    Threshold: <"
            .. tostring(station.enablePercent)
            .. "% / >="
            .. tostring(station.disablePercent)
            .. "%"
        )
        print()
    end
end

--------------------------------------------------
-- Install all stations
--------------------------------------------------

local function installAll()
    clearScreen()
    print("========================================")
    print("             INSTALL MODE")
    print("========================================")
    print()

    local count = askNumber(
        "How many request stations should be bound",
        1,
        1
    )

    local config = {
        version = 2,
        checkInterval = 5,
        stations = {}
    }

    for i = 1, count do
        clearScreen()
        print("========================================")
        print("       Binding Station " .. i .. "/" .. count)
        print("========================================")
        print()

        local entry = bindStation(config, nil)

        if not entry then
            print("Binding cancelled or failed.")
            pause()
            return
        end

        table.insert(config.stations, entry)

        -- Set the final name immediately.
        local physical = peripheral.wrap(entry.physicalStation)
        if physical then
            local ok, err = pcall(function()
                physical.setStationName(entry.stationName)
            end)

            if not ok then
                print("Failed to set station name: " .. tostring(err))
                pause()
                return
            end
        end

        print()
        print("Station " .. i .. " configured successfully.")
        print("Name: " .. entry.stationName)
        print("Item: " .. entry.item)
        pause()
    end

    print()
    local advanced = askYesNo("Enable CLIENT_SERVER mode?", "n")
    if advanced then
        if not configureAdvancedStations(config) then
            print("CLIENT_SERVER configuration cancelled.")
            pause()
            return
        end
    else
        config.advancedNetwork=false
        config.networkMode="STANDALONE"
    end

    if not askYesNo("Write this configuration to config.lua?", "y") then
        print("Installation cancelled.")
        return
    end

    writeConfig(config)
    installStationProgram()
    installInstallerProgram()
    createStartup()

    print("Installation completed.")
    print("Stations configured: " .. tostring(#config.stations))
    pause()
end

--------------------------------------------------
-- Update one station
--------------------------------------------------

local function updateOne()
    local config = loadConfig()

    if not config or #config.stations == 0 then
        print("No existing configuration. Use Install first.")
        pause()
        return
    end

    clearScreen()
    print("========================================")
    print("              UPDATE MODE")
    print("========================================")
    print()

    for i, station in ipairs(config.stations) do
        print("[" .. i .. "] " .. station.stationName)
        print("    Item: " .. station.item)
        print("    Inventory: " .. station.inventoryPeripheral)
        print()
    end

    local index = tonumber(ask("Select station to update"))

    if not index or not config.stations[index] then
        print("Invalid selection.")
        pause()
        return
    end

    local old = config.stations[index]
    local entry = bindStation(config, index)

    if entry and old.advanced then
        local advancedConfig = { stations = { entry } }
        if not configureAdvancedStations(advancedConfig) then
            print("Advanced station update cancelled.")
            pause()
            return
        end
    end

    if not entry then
        print("Update cancelled or failed.")
        pause()
        return
    end

    config.stations[index] = entry

    if not askYesNo("Write this update to config.lua?", "y") then
        print("Update cancelled.")
        pause()
        return
    end

    writeConfig(config)
    installStationProgram()
    installInstallerProgram()
    createStartup()

    print()
    print("Station updated successfully.")
    print("Old station: " .. tostring(old.stationName))
    print("New station: " .. tostring(entry.stationName))
    pause()
end

--------------------------------------------------
-- Find physical station for an existing config entry
--------------------------------------------------

local function findPhysicalStationForEntry(entry)
    -- Fast path: current peripheral identifier
    if entry.physicalStation
        and peripheral.isPresent(entry.physicalStation)
        and peripheral.getType(entry.physicalStation) == "Create_Station" then

        local station = peripheral.wrap(entry.physicalStation)
        if station then
            local ok, currentName = pcall(function()
                return station.getStationName()
            end)

            if ok and (
                currentName == entry.stationName
                or currentName == entry.disabledName
                or currentName == entry.requestName
                or currentName == entry.waitingName
                or currentName == entry.advancedDisabledName
                or currentName == entry.supplyName
            ) then
                return station
            end
        end
    end

    -- Recovery path: peripheral name may have changed.
    for _, peripheralName in ipairs(peripheral.getNames()) do
        if peripheral.getType(peripheralName) == "Create_Station" then
            local station = peripheral.wrap(peripheralName)
            if station then
                local ok, currentName = pcall(function()
                    return station.getStationName()
                end)

                if ok and (
                    currentName == entry.stationName
                    or currentName == entry.disabledName
                ) then
                    return station
                end
            end
        end
    end

    return nil
end

--------------------------------------------------
-- Delete one station
--------------------------------------------------

local function deleteOne()
    local config = loadConfig()

    if not config or #config.stations == 0 then
        print("No existing configuration. Nothing to delete.")
        pause()
        return
    end

    clearScreen()
    print("========================================")
    print("             DELETE STATION")
    print("========================================")
    print()

    for i, station in ipairs(config.stations) do
        print("[" .. i .. "] " .. station.stationName)
        print("    Item: " .. station.item)
        print("    Inventory: " .. station.inventoryPeripheral)
        print()
    end

    local index = tonumber(ask("Select station to delete"))

    if not index or not config.stations[index] then
        print("Invalid selection.")
        pause()
        return
    end

    local entry = config.stations[index]

    print()
    print("Selected station:")
    print("    " .. entry.stationName)
    print("    Item: " .. entry.item)
    print()

    if not askYesNo("Delete this station from the configuration?", "n") then
        print("Delete cancelled.")
        pause()
        return
    end

    -- If the station is currently disabled, restore its normal name
    -- before removing it from the controller configuration.
    local physical = findPhysicalStationForEntry(entry)

    if physical then
        local ok, currentName = pcall(function()
            return physical.getStationName()
        end)

        if ok and currentName == entry.disabledName then
            local renameOk, renameErr = pcall(function()
                physical.setStationName(entry.stationName)
            end)

            if not renameOk then
                print("Failed to restore station name:")
                print(tostring(renameErr))
                print("Delete cancelled.")
                pause()
                return
            end
        end
    end

    table.remove(config.stations, index)

    -- Rebuild ids so they remain compact and deterministic.
    for i, station in ipairs(config.stations) do
        station.id = "station_" .. tostring(i)
    end

    writeConfig(config)
    installStationProgram()
    installInstallerProgram()
    createStartup()

    print()
    print("Station deleted successfully.")
    print("Deleted: " .. entry.stationName)
    print("Remaining stations: " .. tostring(#config.stations))
    pause()
end

--------------------------------------------------
-- Add one station to an existing configuration
--------------------------------------------------

local function addOne()
    local config = loadConfig()

    if not config then
        print("No existing configuration. Use Install first.")
        pause()
        return
    end

    clearScreen()
    print("========================================")
    print("             ADD STATION")
    print("========================================")
    print()
    print("Current stations: " .. tostring(#config.stations))
    print()

    local entry = bindStation(config, nil)

    if entry and config.advancedNetwork then
        local advancedConfig = { stations = { entry } }
        if not configureAdvancedStations(advancedConfig) then
            print("Advanced station add cancelled.")
            pause()
            return
        end
    end

    if not entry then
        print("Add station cancelled or failed.")
        pause()
        return
    end

    table.insert(config.stations, entry)

    local physical = peripheral.wrap(entry.physicalStation)
    if physical then
        local ok, err = pcall(function()
            physical.setStationName(entry.stationName)
        end)

        if not ok then
            table.remove(config.stations)
            print("Failed to set station name: " .. tostring(err))
            pause()
            return
        end
    else
        table.remove(config.stations)
        print("Physical station disappeared during configuration.")
        pause()
        return
    end

    if not askYesNo("Write this station to config.lua?", "y") then
        -- Restore the old station name when user cancels.
        pcall(function()
            physical.setStationName(entry.stationName)
        end)
        table.remove(config.stations)
        print("Add station cancelled.")
        pause()
        return
    end

    writeConfig(config)
    installStationProgram()
    installInstallerProgram()
    createStartup()

    print()
    print("Station added successfully.")
    print("Name: " .. entry.stationName)
    print("Item: " .. entry.item)
    print("Total stations: " .. tostring(#config.stations))
    pause()
end

--------------------------------------------------
-- Run controller
--------------------------------------------------

local function runController()
    if not fs.exists(STATION_PROGRAM_PATH) then
        print("station.lua is not installed.")
        print("Use Install first.")
        pause()
        return
    end

    shell.run("station.lua")
end

--------------------------------------------------
-- Main startup menu
--------------------------------------------------

while true do
    local config = loadConfig()

    showStartupMenu(config)

    local choice, timedOut = timedMenuChoice(5)

    if timedOut then
        print()
        print("No selection. Starting controller...")
        sleep(1)
        runController()

    elseif choice == "1" then
        runController()

    elseif choice == "2" then
        installAll()

    elseif choice == "3" then
        updateOne()

    elseif choice == "4" then
        addOne()

    elseif choice == "5" then
        deleteOne()

    elseif choice == "6" then
        if fs.exists(SERVER_PROGRAM_PATH) or fs.exists("/disk/server.lua") then
            if fs.exists("/disk/server.lua") then installServerProgram() end
            shell.run(SERVER_PROGRAM_PATH, "install")
        else
            print("server.lua is missing from the floppy disk.")
            pause()
        end

    elseif choice == "7" then
        break

    else
        print()
        print("Invalid selection.")
        sleep(1)
    end
end
