--[[
    Create Factory Train Station Controller

    One Computer controls multiple request stations.
    Each station is independently bound to:
      - Create Train Station
      - Inventory peripheral
      - Requested item
      - Capacity / thresholds

    Station names are stable logical identifiers.
    Peripheral names are only used to locate the bound inventory/physical station
    within the current wired factory network.
]]

local CONFIG_PATH = "/config.lua"
local PROTOCOL_PATH = "/protocol.lua"

local protocol = nil

local function loadProtocol()
    if protocol then return protocol end
    if not fs.exists(PROTOCOL_PATH) then return nil end
    local ok, result = pcall(dofile, PROTOCOL_PATH)
    if ok and type(result) == "table" then
        protocol = result
        return protocol
    end
    return nil
end

local rednetOpened = false
local serverByResource = {}
local pausedByResource = {}
local lastRequestAt = {}
local runtimeConfig = nil
local helloInterval = 30
local discoveryWindow = 3
local modemSide = nil

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

local function openRednet()
    if not loadProtocol() then return false end
    if rednetOpened then return true end
    modemSide = findWirelessModem()
    if not modemSide then return false end
    if not rednet.isOpen(modemSide) then
        rednet.open(modemSide)
    end
    rednetOpened = true
    return true
end

local function broadcastMessage(messageType, resourceType, extra)
    if not openRednet() then return false end
    local msg = { protocol = protocol.PROTOCOL, type = messageType }
    if resourceType ~= nil then msg.resourceType = resourceType end
    if type(extra) == "table" then
        for k, v in pairs(extra) do msg[k] = v end
    end
    return rednet.broadcast(msg, protocol.PROTOCOL)
end

local function discoverServers()
    if not openRednet() then return end
    broadcastMessage(protocol.HELLO)
    local deadline = os.clock() + discoveryWindow
    while os.clock() < deadline do
        local timeout = math.max(0.05, deadline - os.clock())
        local sender, message = rednet.receive(protocol.PROTOCOL, timeout)
        if not sender then break end
        if type(message) == "table" and message.type == protocol.ANSWER and message.resourceType then
            if serverByResource[message.resourceType] == nil then
                serverByResource[message.resourceType] = sender
            end
        end
    end
end

local function requestRename(resourceType)
    broadcastMessage(protocol.REQUEST_RENAME, resourceType)
    lastRequestAt[resourceType] = os.clock()
end

local function getResourceCount(device, resourceType, isFluid)
    if not device then return nil end
    if isFluid then
        local ok, tanks = pcall(function() return device.tanks() end)
        if not ok or type(tanks) ~= "table" then return nil end
        local total = 0
        for _, tank in pairs(tanks) do
            if tank and normalizeResourceName(tank.name) == resourceType then total = total + (tank.amount or 0) end
        end
        return total
    end
    local ok, items = pcall(function() return device.list() end)
    if not ok or type(items) ~= "table" then return nil end
    local total = 0
    for _, item in pairs(items) do
        if item and normalizeResourceName(item.name) == resourceType then total = total + (item.count or 0) end
    end
    return total
end

local function trainStorageForStation(entry)
    local names = {}
    if entry.trainStoragePeripheral then table.insert(names, entry.trainStoragePeripheral) end
    for _, name in ipairs(names) do
        if peripheral.isPresent(name) then
            local p = peripheral.wrap(name)
            if p then return p end
        end
    end
    return nil
end

--------------------------------------------------
-- Utilities
--------------------------------------------------

local function log(message)
    print(os.date("[%H:%M:%S] ") .. tostring(message))
end

local function formatNumber(value)
    local number = tonumber(value) or 0
    local formatted = tostring(math.floor(number))
    local output = ""
    local index = 0

    for i = #formatted, 1, -1 do
        output = formatted:sub(i, i) .. output
        index = index + 1
        if index % 3 == 0 and i > 1 then
            output = "," .. output
        end
    end

    return output
end

local function loadConfig()
    local ok, config = pcall(dofile, CONFIG_PATH)

    if not ok or type(config) ~= "table" then
        error("Invalid config.lua: " .. tostring(config))
    end

    config.stations = config.stations or {}
    config.checkInterval = tonumber(config.checkInterval) or 5

    for i, entry in ipairs(config.stations) do
        if type(entry) ~= "table" then
            error("Invalid station entry at index " .. tostring(i))
        end

        -- Older configurations may not have physicalStation.
        -- The station can still be recovered by its logical stationName.
        entry.physicalStation = entry.physicalStation or nil
    end

    return config
end

--------------------------------------------------
-- Peripheral lookup
--------------------------------------------------

local function isManagedStationName(entry, name)
    if name == entry.stationName or name == entry.disabledName then return true end
    if not entry.advanced then return false end
    return name == entry.requestName
        or name == entry.waitingName
        or name == entry.advancedDisabledName
        or name == entry.supplyName
end

local function findStation(entry)
    -- Fast path: current peripheral name still exists and has the right type.
    if entry.physicalStation
        and peripheral.isPresent(entry.physicalStation)
        and peripheral.getType(entry.physicalStation) == "Create_Station" then

        local station = peripheral.wrap(entry.physicalStation)
        if station then
            local ok, name = pcall(function()
                return station.getStationName()
            end)

            if ok and isManagedStationName(entry, name) then
                return station
            end
        end
    end

    -- Recovery path: peripheral number/name may have changed after reconnect/reboot.
    for _, peripheralName in ipairs(peripheral.getNames()) do
        if peripheral.getType(peripheralName) == "Create_Station" then
            local station = peripheral.wrap(peripheralName)
            if station then
                local ok, name = pcall(function()
                    return station.getStationName()
                end)

                if ok and isManagedStationName(entry, name) then
                    entry.physicalStation = peripheralName
                    return station
                end
            end
        end
    end

    return nil
end

local function findInventory(entry)
    if not entry.inventoryPeripheral then
        return nil
    end

    if not peripheral.isPresent(entry.inventoryPeripheral) then
        return nil
    end

    local currentType = peripheral.getType(entry.inventoryPeripheral)

    if entry.inventoryType and currentType ~= entry.inventoryType then
        return nil
    end

    local inventory = peripheral.wrap(entry.inventoryPeripheral)
    if not inventory then
        return nil
    end

    local ok = pcall(function()
        inventory.list()
    end)

    if not ok then
        return nil
    end

    return inventory
end

--------------------------------------------------
-- Inventory
--------------------------------------------------

local function getItemCount(inventory, itemName)
    local ok, items = pcall(function()
        return inventory.list()
    end)

    if not ok or type(items) ~= "table" then
        return nil
    end

    local total = 0

    for _, item in pairs(items) do
        if item and item.name == itemName then
            total = total + (item.count or 0)
        end
    end

    return total
end

local function getPercentage(count, capacity)
    if not capacity or capacity <= 0 then
        return 0
    end

    return count / capacity * 100
end

--------------------------------------------------
-- Station status
--------------------------------------------------

local function getStationName(station)
    local ok, name = pcall(function()
        return station.getStationName()
    end)

    if not ok then
        return nil
    end

    return name
end

local function setStationName(station, name)
    local current = getStationName(station)
    if not current then
        return false
    end

    if current == name then
        return true
    end

    local ok, err = pcall(function()
        station.setStationName(name)
    end)

    if not ok then
        log("Failed to rename station: " .. tostring(err))
        return false
    end

    return true
end

local function updateStationState(station, entry, percent)
    local current = getStationName(station)
    if not current then
        return "error"
    end

    -- State is latched:
    --   - Only inventory below MIN can enable the station.
    --   - Once enabled, it stays enabled until inventory reaches MAX.
    --   - In the middle range, keep the current state unchanged.
    if current == entry.stationName then
        if percent >= entry.disablePercent then
            if setStationName(station, entry.disabledName) then
                return "disabled"
            end
            return "error"
        end

        return "enabled"
    end

    if current == entry.disabledName then
        if percent < entry.enablePercent then
            if setStationName(station, entry.stationName) then
                return "enabled"
            end
            return "error"
        end

        return "disabled"
    end

    -- Unknown/currently inconsistent station name.
    -- Recover using the inventory thresholds:
    -- below MIN -> ENABLE, otherwise stay DISABLED.
    if percent < entry.enablePercent then
        if setStationName(station, entry.stationName) then
            return "enabled"
        end
    else
        if setStationName(station, entry.disabledName) then
            return "disabled"
        end
    end

    return "error"
end

--------------------------------------------------
-- Advanced CLIENT_SERVER demand controller
--------------------------------------------------

local function advancedNames(entry)
    local resource = entry.resourceType or entry.item
    local requestName = entry.requestName or (resource .. "_Request_" .. (entry.factoryId or entry.id or "Factory"))
    return requestName,
        entry.waitingName or ("WATTING_" .. requestName),
        entry.advancedDisabledName or ("DISABLE_" .. requestName)
end

local function setAdvancedName(station, entry, name)
    return setStationName(station, name)
end

local function advancedState(station, entry, inventory, count, percent)
    local resource = entry.resourceType or entry.item
    local requestName, waitingName, disabledName = advancedNames(entry)
    local current = getStationName(station)
    local paused = pausedByResource[resource] == true

    -- Keep the original threshold controller as the demand decision source.
    local needs = percent < (entry.enablePercent or 20)
    local full = percent >= (entry.disablePercent or 80)

    if full then
        if current ~= disabledName then setAdvancedName(station, entry, disabledName) end
        return "disabled"
    end

    if needs then
        if current ~= waitingName and current ~= requestName then
            setAdvancedName(station, entry, waitingName)
            current = waitingName
        end
        if current == requestName then
            -- An ENABLE station which is still below the threshold is already participating.
        elseif not paused and (not lastRequestAt[resource] or os.clock() - lastRequestAt[resource] >= 5) then
            requestRename(resource)
        end
    elseif current == disabledName then
        -- Hysteresis: once blocked, remain blocked until below the enable threshold.
        return "disabled"
    elseif current ~= requestName and current ~= waitingName then
        setAdvancedName(station, entry, requestName)
    end

    -- When a train is physically present, the portable storage interface is the
    -- authoritative view of the train's current load.
    if current == requestName or current == waitingName then
        local trainStorage = trainStorageForStation(entry)
        if trainStorage then
            local trainCount = getResourceCount(trainStorage, resource, entry.resourceKind == "fluid")
            if trainCount ~= nil and trainCount <= 0 then
                broadcastMessage(protocol.NO_RESOURCE, resource)
            end
        end
    end

    if paused then return "waiting" end
    if current == waitingName then return "waiting" end
    if current == requestName then return "enabled" end
    return "disabled"
end

local function handleAdvancedMessage(message)
    if type(message) ~= "table" or message.protocol ~= protocol.PROTOCOL then return end
    local resource = message.resourceType

    if message.type == protocol.ALLOW_RENAME and resource then
        pausedByResource[resource] = false
        if runtimeConfig then
            for _, entry in ipairs(runtimeConfig.stations or {}) do
                if entry.advanced and (entry.resourceType or entry.item) == resource then
                    local station = findStation(entry)
                    if station and getStationName(station) == (entry.waitingName or ("WATTING_" .. (entry.requestName or ""))) then
                        setStationName(station, entry.requestName or ((entry.resourceType or entry.item) .. "_Request_" .. (entry.factoryId or entry.id)))
                    end
                end
            end
        end
        return
    end

    if message.type == protocol.PAUSE and resource then
        pausedByResource[resource] = true
        return
    end

    if message.type == protocol.ENABLE and resource then
        pausedByResource[resource] = false
        if runtimeConfig then
            for _, entry in ipairs(runtimeConfig.stations or {}) do
                if entry.advanced and (entry.resourceType or entry.item) == resource then
                    local station = findStation(entry)
                    if station then
                        local current = getStationName(station)
                        local waitingName = entry.waitingName or ("WATTING_" .. (entry.requestName or ""))
                        if current == waitingName then
                            setStationName(station, entry.requestName or ((entry.resourceType or entry.item) .. "_Request_" .. (entry.factoryId or entry.id)))
                        end
                    end
                end
            end
        end
        return
    end

    if message.type == protocol.ANSWER and resource then
        return
    end
end

local function advancedEventLoop()
    if not openRednet() then return end
    while true do
        local event = { os.pullEvent() }
        if event[1] == "rednet_message" then
            local sender, message, protocolName = event[2], event[3], event[4]
            if protocolName == protocol.PROTOCOL then
                handleAdvancedMessage(message)
            end
        elseif event[1] == "timer" then
            -- timers are handled by the main loop; ignored here
        end
    end
end

--------------------------------------------------
-- Monitor drawing API
--------------------------------------------------

local function getMonitor()
    if peripheral.getType("monitor") == "monitor" then
        return peripheral.wrap("monitor")
    end

    if peripheral.isPresent("monitor_0") and peripheral.getType("monitor_0") == "monitor" then
        return peripheral.wrap("monitor_0")
    end

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            return peripheral.wrap(name)
        end
    end

    return nil
end

local function setMonitorColours(monitor, textColour, backgroundColour)
    if monitor.setBackgroundColour then
        monitor.setBackgroundColour(backgroundColour or colors.black)
        monitor.setTextColour(textColour or colors.white)
    else
        monitor.setBackgroundColor(backgroundColour or colors.black)
        monitor.setTextColor(textColour or colors.white)
    end
end

local function drawHorizontalLine(monitor, y, colour)
    local width = select(1, monitor.getSize())
    setMonitorColours(monitor, colour or colors.blue, colors.black)
    monitor.setCursorPos(1, y)
    monitor.write(string.rep("=", width))
end

local function centerText(monitor, y, text, colour)
    local width = select(1, monitor.getSize())
    local value = tostring(text or "")

    if #value > width then
        value = value:sub(1, width)
    end

    local x = math.max(1, math.floor((width - #value) / 2) + 1)

    setMonitorColours(monitor, colour or colors.white, colors.black)
    monitor.setCursorPos(x, y)
    monitor.write(value)
end

local function drawProgressBar(
    monitor,
    x,
    y,
    width,
    percent,
    lowThreshold
)
    local clamped =
        math.max(
            0,
            math.min(
                100,
                tonumber(percent) or 0
            )
        )

    local filled =
        math.floor(
            width * clamped / 100
        )

    -- Stock is only red when it is below the station's
    -- configured minimum/enable threshold.
    local fillColour = colors.lime

    if clamped < (tonumber(lowThreshold) or 0) then
        fillColour = colors.red
    end

    paintutils.drawFilledBox(
        x,
        y,
        x + width - 1,
        y + 1,
        colors.gray
    )

    if filled > 0 then
        paintutils.drawFilledBox(
            x,
            y,
            x + filled - 1,
            y + 1,
            fillColour
        )
    end
end

local function drawStatusText(monitor, x, y, state)
    local label = "ENABLE"
    local colour = colors.lime

    if state == "disabled" then
        label = "DISABLE"
        colour = colors.red
    elseif state == "error" then
        label = "ERROR"
        colour = colors.orange
    end

    setMonitorColours(
        monitor,
        colour,
        colors.black
    )

    monitor.setCursorPos(x, y)
    monitor.write(label)
end


local function shortName(value, width)
    local text = tostring(value or "")
    width = tonumber(width) or 1

    if width <= 0 then
        return ""
    end

    if #text <= width then
        return text
    end

    if width <= 3 then
        return text:sub(1, width)
    end

    return text:sub(1, width - 3) .. "..."
end


local function drawDashboard(monitor, rows)
    if not monitor then
        return
    end

    monitor.setTextScale(0.5)
    monitor.clear()
    setMonitorColours(
        monitor,
        colors.white,
        colors.black
    )

    local width, height = monitor.getSize()

    centerText(
        monitor,
        1,
        "FACTORY REQUEST CONTROLLER",
        colors.white
    )

    centerText(
        monitor,
        2,
        "MULTI-STATION STATUS",
        colors.cyan
    )

    drawHorizontalLine(
        monitor,
        4,
        colors.blue
    )

    -- Layout:
    -- Station name and status share the first line.
    -- Station/status and item name share the first row.
    -- Actual / maximum + percentage is directly below the item.
    local statusWidth =
        math.max(
            10,
            math.floor(width * 0.16)
        )

    local contentWidth =
        width - statusWidth - 3

    local stationWidth =
        math.max(
            18,
            math.floor(contentWidth * 0.42)
        )

    local itemWidth =
        math.max(
            18,
            contentWidth - stationWidth - 2
        )

    local statusX =
        width - statusWidth + 1

    local maxRows =
        math.max(
            1,
            math.floor((height - 8) / 3)
        )

    local shown =
        math.min(
            #rows,
            maxRows
        )

    -- Header
    setMonitorColours(
        monitor,
        colors.lightGray,
        colors.black
    )

    monitor.setCursorPos(1, 5)
    monitor.write(
        shortName(
            "STATION",
            stationWidth
        )
    )

    monitor.setCursorPos(
        stationWidth + 3,
        5
    )

    monitor.write(
        shortName(
            "ITEM",
            itemWidth
        )
    )

    monitor.setCursorPos(
        statusX,
        5
    )

    monitor.write(
        shortName(
            "STATUS",
            statusWidth
        )
    )

    local y = 6

    for i = 1, shown do

        local row = rows[i]

        --------------------------------------------------
        -- Station name
        --------------------------------------------------

        setMonitorColours(
            monitor,
            colors.white,
            colors.black
        )

        monitor.setCursorPos(
            1,
            y
        )

        monitor.write(
            shortName(
                row.stationName,
                stationWidth
            )
        )

        --------------------------------------------------
        -- Station status
        --
        -- ENABLE = green
        -- DISABLE = red
        --------------------------------------------------

        drawStatusText(
            monitor,
            statusX,
            y,
            row.state
        )

        --------------------------------------------------
        -- Item name
        --------------------------------------------------

        setMonitorColours(
            monitor,
            colors.cyan,
            colors.black
        )

        monitor.setCursorPos(
            stationWidth + 3,
            y
        )

        monitor.write(
            shortName(
                row.item,
                itemWidth
            )
        )

        --------------------------------------------------
        -- Actual / maximum + percentage
        --
        -- Red ONLY when below MIN.
        -- Otherwise green.
        --------------------------------------------------

        local stockColour =
            colors.lime

        if row.state == "error" then
            stockColour = colors.orange
        elseif row.percent < row.enablePercent then
            stockColour = colors.red
        end

        local stockText =
            formatNumber(row.count)
            .. " / "
            .. formatNumber(row.capacity)
            .. "  "
            .. string.format(
                "%.1f%%",
                row.percent
            )

        setMonitorColours(
            monitor,
            stockColour,
            colors.black
        )

        monitor.setCursorPos(
            stationWidth + 3,
            y + 1
        )

        monitor.write(
            shortName(
                stockText,
                itemWidth
            )
        )

        y = y + 3
    end

    --------------------------------------------------
    -- Fixed-color legend
    --------------------------------------------------

    drawHorizontalLine(
        monitor,
        height - 2,
        colors.blue
    )

    setMonitorColours(
        monitor,
        colors.lime,
        colors.black
    )

    monitor.setCursorPos(
        2,
        height - 1
    )

    monitor.write(
        "ENABLE < MIN"
    )

    setMonitorColours(
        monitor,
        colors.orange,
        colors.black
    )

    monitor.setCursorPos(
        math.max(
            18,
            math.floor(width / 2)
        ),
        height - 1
    )

    monitor.write(
        "DISABLE >= MAX"
    )
end

--------------------------------------------------
-- Main controller
--------------------------------------------------

local config = loadConfig()
runtimeConfig = config
local monitor = getMonitor()

local function selfCheck()
    local problems = {}
    if type(config) ~= "table" then
        table.insert(problems, "config.lua invalid")
    end
    if type(config.stations) ~= "table" or #config.stations == 0 then
        table.insert(problems, "no stations configured")
    end
    if config.advancedNetwork then
        if not loadProtocol() then
            table.insert(problems, "protocol.lua missing or invalid")
        end
        if not openRednet() then
            table.insert(problems, "wireless modem_x not found (modem_x must be wireless)")
        end
        for i, entry in ipairs(config.stations or {}) do
            if entry.advanced then
                if not findStation(entry) then
                    table.insert(problems, "station " .. i .. " not found")
                end
                if not findInventory(entry) then
                    table.insert(problems, "inventory " .. i .. " not found")
                end
                if not entry.trainStoragePeripheral or not peripheral.isPresent(entry.trainStoragePeripheral) then
                    table.insert(problems, "train storage " .. i .. " not found")
                end
            end
        end
    end

    if #problems > 0 then
        term.clear()
        term.setCursorPos(1, 1)
        print("CLIENT SELF-CHECK FAILED")
        print()
        for _, problem in ipairs(problems) do
            print("- " .. problem)
        end
        error("Client self-check failed")
    end
end

selfCheck()

term.clear()
term.setCursorPos(1, 1)

print("========================================")
print("      Factory Train Station Controller")
print("========================================")
print()
print("Stations: " .. tostring(#config.stations))
print()

if config.advancedNetwork then
    openRednet()
    discoverServers()
end

local function controllerLoop()
while true do
    local rows = {}

    for i, entry in ipairs(config.stations) do
        local row = {
            stationName = entry.stationName,
            item = entry.item,
            percent = 0,
            count = 0,
            capacity = entry.capacity or 0,
            enablePercent = entry.enablePercent or 20,
            disablePercent = entry.disablePercent or 80,
            state = "error"
        }

        local station = findStation(entry)
        local inventory = findInventory(entry)

        if not station then
            log("[" .. i .. "] Station not found: " .. entry.stationName)
        elseif not inventory then
            log("[" .. i .. "] Inventory not found: " .. entry.inventoryPeripheral)
        else
            local count = getItemCount(inventory, entry.item)

            if count == nil then
                log("[" .. i .. "] Failed to read inventory: " .. entry.inventoryPeripheral)
            else
                local percent = getPercentage(count, entry.capacity)
                local state
                if entry.advanced then
                    state = advancedState(station, entry, inventory, count, percent)
                else
                    state = updateStationState(station, entry, percent)
                end

                row.count = count
                row.percent = percent
                row.state = state

                log(string.format(
                    "[%d] %s | %s | %s / %s (%.1f%%) | %s",
                    i,
                    entry.stationName,
                    entry.item,
                    formatNumber(count),
                    formatNumber(entry.capacity),
                    percent,
                    state
                ))
            end
        end

        table.insert(rows, row)
    end

    if monitor then
        drawDashboard(monitor, rows)
    end

    sleep(config.checkInterval)
end
end

if config.advancedNetwork then
    parallel.waitForAny(controllerLoop, advancedEventLoop)
else
    controllerLoop()
end
