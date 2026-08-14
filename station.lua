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

local function drawStatusText(
    monitor,
    x,
    y,
    state
)
    local label = "ONLINE"
    local colour = colors.lime

    if state == "disabled" then
        label = "OFFLINE"
        -- OFFLINE is still a normal station state, not a low-stock alarm.
        -- Per the requested UI semantics, only low stock is red.
        colour = colors.lime
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

local function drawDashboard(
    monitor,
    rows
)
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

    local width, height =
        monitor.getSize()

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

    --------------------------------------------------
    -- Layout
    --
    -- STATION : 30%
    -- ITEM    : 35%
    -- STOCK   : 25%
    -- STATUS  : remaining
    --
    -- The stock column contains:
    --     actual / maximum  xx.x%
    --------------------------------------------------

    local stationWidth =
        math.max(
            16,
            math.floor(width * 0.30)
        )

    local itemWidth =
        math.max(
            20,
            math.floor(width * 0.35)
        )

    local stockWidth =
        math.max(
            18,
            math.floor(width * 0.25)
        )

    local statusStart =
        stationWidth
        + itemWidth
        + stockWidth
        + 4

    -- Prevent the status column from falling outside the display.
    if statusStart > width - 7 then
        stockWidth =
            math.max(
                14,
                width
                    - stationWidth
                    - itemWidth
                    - 12
            )

        statusStart =
            stationWidth
            + itemWidth
            + stockWidth
            + 4
    end

    --------------------------------------------------
    -- Column headers
    --------------------------------------------------

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
        stationWidth + 2,
        5
    )

    monitor.write(
        shortName(
            "ITEM",
            itemWidth
        )
    )

    monitor.setCursorPos(
        stationWidth
        + itemWidth
        + 3,
        5
    )

    monitor.write(
        shortName(
            "STOCK",
            stockWidth
        )
    )

    monitor.setCursorPos(
        statusStart,
        5
    )

    monitor.write("STATUS")

    --------------------------------------------------
    -- Rows
    --------------------------------------------------

    local usableHeight =
        height - 6

    local rowHeight = 3

    local maxRows =
        math.max(
            1,
            math.floor(
                usableHeight / rowHeight
            )
        )

    local shown =
        math.min(
            #rows,
            maxRows
        )

    local y = 6

    for i = 1, shown do

        local row = rows[i]

        --------------------------------------------------
        -- Station
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
        -- Item
        --------------------------------------------------

        setMonitorColours(
            monitor,
            colors.cyan,
            colors.black
        )

        monitor.setCursorPos(
            stationWidth + 2,
            y
        )

        monitor.write(
            shortName(
                row.item,
                itemWidth
            )
        )

        --------------------------------------------------
        -- Stock
        --
        -- Example:
        -- 3,215/4,096 78.5%
        --------------------------------------------------

        local stockX =
            stationWidth
            + itemWidth
            + 3

        local stockText =
            formatNumber(
                row.count
            )
            .. "/"
            .. formatNumber(
                row.capacity
            )
            .. " "
            .. string.format(
                "%.1f%%",
                row.percent
            )

        local stockColour =
            colors.lime

        if row.state == "error" then
            stockColour = colors.orange
        elseif row.percent
            < row.enablePercent then
            stockColour = colors.red
        end

        setMonitorColours(
            monitor,
            stockColour,
            colors.black
        )

        monitor.setCursorPos(
            stockX,
            y
        )

        monitor.write(
            shortName(
                stockText,
                stockWidth
            )
        )

        --------------------------------------------------
        -- Stock progress bar
        --------------------------------------------------

        local progressWidth =
            math.max(
                8,
                math.min(
                    stockWidth - 2,
                    20
                )
            )

        drawProgressBar(
            monitor,
            stockX,
            y + 1,
            progressWidth,
            row.percent,
            row.enablePercent
        )

        --------------------------------------------------
        -- Status
        --------------------------------------------------

        drawStatusText(
            monitor,
            statusStart,
            y,
            row.state
        )

        y =
            y + rowHeight
    end

    --------------------------------------------------
    -- Footer
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
        colors.white,
        colors.black
    )

    monitor.setCursorPos(
        math.max(
            16,
            math.floor(
                width / 2
            )
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
