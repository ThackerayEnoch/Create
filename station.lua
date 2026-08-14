--[[
    Create Train Station Unloading Controller

    Features:

    1. Find the Create Station by station name from config.lua
    2. Find the inventory using the peripheral name selected during installation
    3. Count the specified item quantity
    4. If inventory < enablePercent
       -> restore the normal station name
       -> allow train pathfinding

    5. If inventory >= disablePercent
       -> rename to disabledName
       -> exclude it from wildcard requests

    6. 20% ~ 80%
       -> keep the current status and avoid frequent renaming

    7. The computer automatically resumes operation after reboot
]]


--------------------------------------------------
-- Load config
--------------------------------------------------

local config = dofile("/config.lua")


--------------------------------------------------
-- Log function
--------------------------------------------------

local function log(message)

    print(
        os.date("[%H:%M:%S] ")
        .. tostring(message)
    )

end


--------------------------------------------------
-- Find Train Station
--
-- Do not use peripheral names such as Create_Station_4
-- Instead, find it by the formal station name
--------------------------------------------------

local function findStation()

    for _, peripheralName
        in ipairs(peripheral.getNames()) do

        --------------------------------------------------
        -- Check whether it is a Create Station
        --------------------------------------------------

        if peripheral.getType(peripheralName)
            == "Create_Station" then

            local station =
                peripheral.wrap(
                    peripheralName
                )

            if station then

                --------------------------------------------------
                -- Get the current station name
                --------------------------------------------------

                local ok, stationName =
                    pcall(function()

                        return station.getStationName()

                    end)


                if ok
                    and stationName then

                    --------------------------------------------------
                    -- Normal name
                    --------------------------------------------------

                    if stationName
                        == config.stationName then

                        return station

                    end


                    --------------------------------------------------
                    -- Disabled state
                    --
                    -- Even if the current name is xxx_DISABLED,
                    -- it must still be found
                    --------------------------------------------------

                    if stationName
                        == config.disabledName then

                        return station

                    end

                end
            end
        end
    end


    return nil
end


--------------------------------------------------
-- Find inventory
--
-- In this version, inventory is found by the peripheral name
-- saved by install.lua
--------------------------------------------------

local function findInventory()

    local name =
        config.inventoryPeripheral


    if not name then

        return nil

    end


    --------------------------------------------------
    -- Check whether the device still exists
    --------------------------------------------------

    if not peripheral.isPresent(name) then

        return nil

    end


    --------------------------------------------------
    -- Check device type
    --------------------------------------------------

    local currentType =
        peripheral.getType(name)


    if config.inventoryType
        and currentType
        ~= config.inventoryType then

        return nil

    end


    --------------------------------------------------
    -- Get peripheral
    --------------------------------------------------

    local inventory =
        peripheral.wrap(name)


    if not inventory then

        return nil

    end


    --------------------------------------------------
    -- Test list()
    --------------------------------------------------

    local ok =
        pcall(function()

            inventory.list()

        end)


    if not ok then

        return nil

    end


    return inventory
end


--------------------------------------------------
-- Read the specified item quantity
--------------------------------------------------

local function getItemCount(
    inventory
)

    local ok, items =
        pcall(function()

            return inventory.list()

        end)


    if not ok then

        return nil
    end


    if type(items) ~= "table" then

        return nil
    end


    local total = 0


    for _, item in pairs(items) do

        if item
            and item.name
            == config.item then

            total =
                total
                + (item.count or 0)

        end
    end


    return total
end


--------------------------------------------------
-- Get inventory percentage
--------------------------------------------------

local function getPercentage(
    count
)

    return
        count
        / config.capacity
        * 100

end


local function formatNumber(value)

    local number = tonumber(value) or 0

    if number >= 1000 then

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

    return tostring(math.floor(number))
end


local function getMonitor()

    if config.monitorSide then

        local side = tostring(config.monitorSide)

        if peripheral.isPresent(side)
            and peripheral.getType(side) == "monitor" then

            return peripheral.wrap(side)
        end
    end

    for _, peripheralName in ipairs(peripheral.getNames()) do

        if peripheral.getType(peripheralName) == "monitor" then

            return peripheral.wrap(peripheralName)
        end
    end

    return nil
end


local function setMonitorColours(monitor, textColour, backgroundColour)

    if not monitor then

        return
    end

    if monitor.setBackgroundColour then

        monitor.setBackgroundColour(backgroundColour or colors.black)
        monitor.setTextColour(textColour or colors.white)

    else

        monitor.setBackgroundColor(backgroundColour or colors.black)
        monitor.setTextColor(textColour or colors.white)
    end
end


local function drawPixelLine(monitor, x1, y1, x2, y2, colour)

    if not monitor or not monitor.drawPixel then

        return
    end

    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy

    while true do

        monitor.drawPixel(x1, y1, colour)

        if x1 == x2 and y1 == y2 then
            break
        end

        local e2 = err * 2

        if e2 > -dy then
            err = err - dy
            x1 = x1 + sx
        end

        if e2 < dx then
            err = err + dx
            y1 = y1 + sy
        end
    end
end


local function drawPixelRect(monitor, x1, y1, x2, y2, colour)

    if not monitor or not monitor.drawPixel then

        return
    end

    if x1 > x2 then
        local temp = x1
        x1 = x2
        x2 = temp
    end

    if y1 > y2 then
        local temp = y1
        y1 = y2
        y2 = temp
    end

    for y = y1, y2 do

        for x = x1, x2 do
            monitor.drawPixel(x, y, colour)
        end
    end
end


local function drawMonitorText(monitor, x, y, text, colour)

    if not monitor then

        return
    end

    if monitor.setCursorPos then

        monitor.setCursorPos(x, y)
        monitor.setTextColour(colour or colors.white)
        monitor.write(text)
        return
    end

    if monitor.drawText then
        monitor.drawText(x, y, text, colour or colors.white)
    end
end


local function supportsAdvancedGraphics(monitor)

    return monitor and monitor.drawPixel ~= nil
end


local function prettyItemName(rawName)

    local item = tostring(rawName or "item")
    item = item:gsub("^.-:", "")
    item = item:gsub("_", " ")
    item = item:gsub("%s+", " ")
    item = item:gsub("^%s*(.-)%s*$", "%1")

    if item == "" then
        return "ITEM REQUEST"
    end

    local parts = {}

    for part in item:gmatch("%S+") do
        table.insert(parts, part)
    end

    if #parts == 0 then
        return "ITEM REQUEST"
    end

    local output = ""

    for i, part in ipairs(parts) do

        if i > 1 then
            output = output .. " "
        end

        output = output .. string.upper(part)
    end

    if not output:match("REQUEST") then
        output = output .. " REQUEST"
    end

    return output
end


local function prettyStationName(rawName)

    local name = tostring(rawName or "Station")
    name = name:gsub("^.-_", "")
    name = name:gsub("_", " ")
    name = name:gsub("%s+", " ")
    name = name:gsub("^%s*(.-)%s*$", "%1")

    if name == "" then
        return "STATION STATUS"
    end

    local output = ""

    for part in name:gmatch("%S+") do

        if output ~= "" then
            output = output .. " "
        end

        output = output .. string.upper(part)
    end

    if output == "" then
        return "STATION STATUS"
    end

    return output
end


local function drawMonitorStatus(monitor, count, total, percent, state)

    if not monitor then

        return
    end

    local actualPercent = tonumber(percent) or 0
    local barPercent = actualPercent

    if barPercent > 100 then
        barPercent = 100
    elseif barPercent < 0 then
        barPercent = 0
    end

    local title = prettyItemName(config.item)
    local subtitle = prettyStationName(config.stationName)
    local usageLabel = "REQUEST ENABLED"

    if state == "disabled" then
        usageLabel = "REQUEST DISABLED"
    elseif state == "hold" then
        usageLabel = "REQUEST HOLD"
    end

    local width, height = monitor.getSize()
    local maxX = width or 32
    local maxY = height or 20

    if monitor.setTextScale then
        monitor.setTextScale(0.5)
    end

    monitor.clear()

    if not supportsAdvancedGraphics(monitor) then

        setMonitorColours(monitor, colors.white, colors.black)
        monitor.setCursorPos(1, 1)
        monitor.write(title)
        monitor.setCursorPos(1, 2)
        monitor.write(subtitle)
        monitor.setCursorPos(1, 3)
        monitor.write(formatNumber(count) .. " / " .. formatNumber(total))
        monitor.setCursorPos(1, 4)
        monitor.write(string.format("%.1f%%", actualPercent))
        monitor.setCursorPos(1, 5)
        monitor.write(usageLabel)
        return
    end

    local borderColour = colors.lightGray
    local panelColour = colors.black
    local fillColour = colors.gray
    local accentColour = colors.lime

    if state == "disabled" then
        accentColour = colors.red
    elseif state == "hold" then
        accentColour = colors.yellow
    end

    drawPixelRect(monitor, 1, 1, maxX, maxY, borderColour)
    drawPixelRect(monitor, 2, 2, maxX - 1, maxY - 1, panelColour)

    local innerX1 = 3
    local innerX2 = maxX - 2
    local innerY1 = 3
    local innerY2 = maxY - 2

    for y = innerY1, innerY2 do
        for x = innerX1, innerX2 do
            if x == innerX1 or x == innerX2 or y == innerY1 or y == innerY2 then
                monitor.drawPixel(x, y, borderColour)
            end
        end
    end

    drawPixelRect(monitor, 4, 4, maxX - 3, 4, borderColour)
    drawPixelRect(monitor, 4, 5, maxX - 3, 5, fillColour)

    local titleColour = colors.white
    local subtitleColour = colors.white
    if state == "disabled" then
        titleColour = colors.red
    elseif state == "enabled" then
        titleColour = colors.lime
    else
        titleColour = colors.yellow
    end

    drawMonitorText(monitor, 5, 2, title, titleColour)
    drawMonitorText(monitor, 5, 3, subtitle, subtitleColour)

    local dividerY = 7
    drawPixelLine(monitor, 4, dividerY, maxX - 3, dividerY, borderColour)

    drawMonitorText(monitor, 5, 9, "ITEM INVENTORY", colors.lightGray)
    drawMonitorText(monitor, 5, 10, formatNumber(count) .. " / " .. formatNumber(total), colors.white)

    local barX = 5
    local barY = 12
    local barW = 22
    local barH = 2
    local filledW = math.floor((barPercent / 100) * barW)
    if filledW > barW then
        filledW = barW
    end

    drawPixelRect(monitor, barX, barY, barX + barW - 1, barY + barH - 1, colors.gray)
    drawPixelRect(monitor, barX, barY, barX + filledW - 1, barY + barH - 1, accentColour)

    drawMonitorText(monitor, 5, 15, string.format("%.1f%%", actualPercent), colors.white)
    drawMonitorText(monitor, 5, 16, usageLabel, accentColour)

    drawPixelLine(monitor, 4, 18, maxX - 3, 18, borderColour)
    drawMonitorText(monitor, 5, 19, "< " .. tostring(config.enablePercent) .. "% ENABLE", colors.lime)
    drawMonitorText(monitor, 5, 20, ">= " .. tostring(config.disablePercent) .. "% DISABLE", colors.red)
end


--------------------------------------------------
-- Get the current station name
--------------------------------------------------

local function getStationName(
    station
)

    local ok, name =
        pcall(function()

            return station.getStationName()

        end)


    if not ok then

        return nil
    end


    return name
end


--------------------------------------------------
-- Set station name
--------------------------------------------------

local function setStationName(
    station,
    name
)

    local currentName =
        getStationName(
            station
        )


    if not currentName then

        return false
    end


    --------------------------------------------------
    -- The name is already correct, no need to change it
    --------------------------------------------------

    if currentName == name then

        return true
    end


    --------------------------------------------------
    -- Rename
    --------------------------------------------------

    local ok, err =
        pcall(function()

            station.setStationName(
                name
            )

        end)


    if not ok then

        log(
            "Failed to rename station: "
            .. tostring(err)
        )

        return false
    end


    return true
end


--------------------------------------------------
-- Enable station
--------------------------------------------------

local function enableStation(
    station
)

    local currentName =
        getStationName(
            station
        )


    if not currentName then

        return false
    end


    --------------------------------------------------
    -- Already in normal state
    --------------------------------------------------

    if currentName
        == config.stationName then

        return true
    end


    log(
        "Inventory is below the threshold; restoring station"
    )


    local success =
        setStationName(
            station,
            config.stationName
        )


    if success then

        log(
            "Station ENABLED"
        )

        log(
            "Name: "
            .. config.stationName
        )

    end


    return success
end


--------------------------------------------------
-- Disable station
--------------------------------------------------

local function disableStation(
    station
)

    local currentName =
        getStationName(
            station
        )


    if not currentName then

        return false
    end


    --------------------------------------------------
    -- Already in disabled state
    --------------------------------------------------

    if currentName
        == config.disabledName then

        return true
    end


    log(
        "Inventory has reached the disable threshold; disabling station"
    )


    local success =
        setStationName(
            station,
            config.disabledName
        )


    if success then

        log(
            "Station DISABLED"
        )

        log(
            "Name: "
            .. config.disabledName
        )

    end


    return success
end


--------------------------------------------------
-- Display status
--------------------------------------------------

local function printStatus(
    station,
    count,
    percent
)

    local stationName =
        getStationName(
            station
        )


    print()
    print("----------------------------------------")

    print(
        "Station : "
        .. tostring(stationName)
    )

    print(
        "Item    : "
        .. tostring(config.item)
    )

    print(
        "Storage : "
        .. tostring(count)
        .. " / "
        .. tostring(config.capacity)
    )

    print(
        "Usage   : "
        .. string.format(
            "%.2f",
            percent
        )
        .. "%"
    )

    print(
        "Enable  : < "
        .. tostring(
            config.enablePercent
        )
        .. "%"
    )

    print(
        "Disable : >= "
        .. tostring(
            config.disablePercent
        )
        .. "%"
    )

    print("----------------------------------------")
end


--------------------------------------------------
-- Startup info
--------------------------------------------------

local monitor = getMonitor()

term.clear()
term.setCursorPos(1, 1)


print("========================================")
print(" Create Train Station Controller")
print("========================================")
print()

print(
    "Station: "
    .. config.stationName
)

print(
    "Inventory: "
    .. config.inventoryPeripheral
)

print(
    "Item: "
    .. config.item
)

print()


--------------------------------------------------
-- Main loop
--------------------------------------------------

while true do

    --------------------------------------------------
    -- Find station
    --------------------------------------------------

    local station =
        findStation()


    if not station then

        log(
            "ERROR: Train Station not found."
        )

        log(
            "Searching again in 5 seconds..."
        )

        sleep(5)

    else

        --------------------------------------------------
        -- Find inventory
        --------------------------------------------------

        local inventory =
            findInventory()


        if not inventory then

            log(
                "ERROR: Inventory not found."
            )

            log(
                "Peripheral: "
                .. tostring(
                    config.inventoryPeripheral
                )
            )

            sleep(5)

        else

            --------------------------------------------------
            -- Read item
            --------------------------------------------------

            local count =
                getItemCount(
                    inventory
                )


            if count == nil then

                log(
                    "ERROR: Cannot read inventory."
                )

                sleep(5)

            else

                --------------------------------------------------
                -- Calculate percentage
                --------------------------------------------------

                local percent =
                    getPercentage(
                        count
                    )


                --------------------------------------------------
                -- Display
                --------------------------------------------------

                printStatus(
                    station,
                    count,
                    percent
                )

                if monitor then

                    local state = "hold"

                    if percent < config.enablePercent then
                        state = "enabled"
                    elseif percent >= config.disablePercent then
                        state = "disabled"
                    end

                    drawMonitorStatus(
                        monitor,
                        count,
                        config.capacity,
                        percent,
                        state
                    )
                end


                --------------------------------------------------
                -- Status check
                --------------------------------------------------

                if percent
                    < config.enablePercent then

                    --------------------------------------------------
                    -- Inventory low
                    -- Open request station
                    --------------------------------------------------

                    enableStation(
                        station
                    )


                elseif percent
                    >= config.disablePercent then

                    --------------------------------------------------
                    -- Inventory high
                    -- Block request station
                    --------------------------------------------------

                    disableStation(
                        station
                    )


                else

                    --------------------------------------------------
                    -- Middle range
                    -- Do not change state
                    --------------------------------------------------

                    log(
                        "Keep the current station state"
                    )

                end


                sleep(
                    config.checkInterval
                )

            end
        end
    end

end