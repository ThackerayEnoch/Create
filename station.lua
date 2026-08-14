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
    config.checkInterval = config.checkInterval or 5
    return config
end

--------------------------------------------------
-- Peripheral lookup
--------------------------------------------------

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

            if ok and (name == entry.stationName or name == entry.disabledName) then
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

                if ok and (name == entry.stationName or name == entry.disabledName) then
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

    if percent < entry.enablePercent then
        if current ~= entry.stationName then
            setStationName(station, entry.stationName)
        end
        return "enabled"
    end

    if percent >= entry.disablePercent then
        if current ~= entry.disabledName then
            setStationName(station, entry.disabledName)
        end
        return "disabled"
    end

    if current == entry.disabledName then
        return "disabled"
    end

    return "enabled"
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

local function drawProgressBar(monitor, x, y, width, percent)
    local clamped = math.max(0, math.min(100, tonumber(percent) or 0))
    local filled = math.floor(width * clamped / 100)

    paintutils.drawFilledBox(
        x,
        y,
        x + width - 1,
        y + 1,
        colors.gray
    )

    if filled > 0 then
        local fillColour = colors.lime

        if clamped >= 80 then
            fillColour = colors.red
        elseif clamped >= 60 then
            fillColour = colors.yellow
        end

        paintutils.drawFilledBox(
            x,
            y,
            x + filled - 1,
            y + 1,
            fillColour
        )
    end
end

local function drawStatusBox(monitor, x, y, width, state)
    local borderColour = colors.lime
    local statusColour = colors.lime
    local text = "REQUEST ENABLED"

    if state == "disabled" then
        borderColour = colors.red
        statusColour = colors.red
        text = "REQUEST DISABLED"
    elseif state == "error" then
        borderColour = colors.orange
        statusColour = colors.orange
        text = "ERROR"
    end

    paintutils.drawBox(
        x,
        y,
        x + width - 1,
        y + 2,
        borderColour
    )

    setMonitorColours(monitor, statusColour, colors.black)
    monitor.setCursorPos(x + 3, y + 1)
    monitor.write(text)
end

local function shortName(name, width)
    local value = tostring(name or "")
    if #value <= width then
        return value
    end
    if width <= 3 then
        return value:sub(1, width)
    end
    return value:sub(1, width - 3) .. "..."
end

local function drawDashboard(monitor, rows)
    if not monitor then
        return
    end

    monitor.setTextScale(0.5)
    monitor.clear()
    setMonitorColours(monitor, colors.white, colors.black)

    local width, height = monitor.getSize()

    centerText(monitor, 1, "FACTORY REQUEST CONTROLLER", colors.white)
    centerText(monitor, 2, "MULTI-STATION STATUS", colors.cyan)
    drawHorizontalLine(monitor, 4, colors.blue)

    local usableHeight = height - 6
    local rowHeight = 3
    local maxRows = math.max(1, math.floor(usableHeight / rowHeight))
    local shown = math.min(#rows, maxRows)

    -- Keep the station and item columns wide enough for real factory names.
    -- The progress/status column gets the remaining space.
    -- Give the item column the most space because item IDs/names are often long.
    -- Layout target: STATION ~30%, ITEM ~45%, STOCK ~25%.
    local nameWidth = math.max(14, math.floor(width * 0.30))
    local itemWidth = math.max(22, math.floor(width * 0.45))
    local barStart = nameWidth + itemWidth + 4
    local barWidth = math.max(8, width - barStart - 8)

    -- Column headers
    setMonitorColours(monitor, colors.lightGray, colors.black)
    monitor.setCursorPos(1, 5)
    monitor.write(shortName("STATION", nameWidth))
    monitor.setCursorPos(nameWidth + 2, 5)
    monitor.write(shortName("ITEM", itemWidth))
    monitor.setCursorPos(barStart, 5)
    monitor.write("STOCK")

    local y = 6

    for i = 1, shown do
        local row = rows[i]
        local stateColour = colors.lime

        if row.state == "disabled" then
            stateColour = colors.red
        elseif row.state == "error" then
            stateColour = colors.orange
        end

        -- Station name column
        setMonitorColours(monitor, colors.white, colors.black)
        monitor.setCursorPos(1, y)
        monitor.write(shortName(row.stationName, nameWidth))

        -- Item column: wider than the previous layout
        setMonitorColours(monitor, colors.cyan, colors.black)
        monitor.setCursorPos(nameWidth + 2, y)
        monitor.write(shortName(row.item, itemWidth))

        -- Progress bar in the remaining column
        drawProgressBar(
            monitor,
            barStart,
            y,
            barWidth,
            row.percent
        )

        -- Percentage and status below the item/progress row
        setMonitorColours(monitor, stateColour, colors.black)
        monitor.setCursorPos(nameWidth + 2, y + 1)
        monitor.write(string.format("%6.1f%%", row.percent))

        monitor.setCursorPos(barStart, y + 1)
        monitor.write(row.state == "enabled" and "ONLINE"
            or row.state == "disabled" and "OFFLINE"
            or "ERROR")

        y = y + rowHeight
    end

    drawHorizontalLine(monitor, height - 2, colors.blue)

    setMonitorColours(monitor, colors.lime, colors.black)
    monitor.setCursorPos(2, height - 1)
    monitor.write("ENABLE < 20%")

    setMonitorColours(monitor, colors.red, colors.black)
    monitor.setCursorPos(math.max(16, math.floor(width / 2)), height - 1)
    monitor.write("DISABLE >= 80%")
end

--------------------------------------------------
-- Main controller
--------------------------------------------------

local config = loadConfig()
local monitor = getMonitor()

term.clear()
term.setCursorPos(1, 1)

print("========================================")
print("      Factory Train Station Controller")
print("========================================")
print()
print("Stations: " .. tostring(#config.stations))
print()

while true do
    local rows = {}

    for i, entry in ipairs(config.stations) do
        local row = {
            stationName = entry.stationName,
            item = entry.item,
            percent = 0,
            count = 0,
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
                local state = updateStationState(station, entry, percent)

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
