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

    local title = prettyItemName(config.item)
    local subtitle = prettyStationName(config.stationName)
    local usageLabel = "REQUEST ENABLED"
    local actualPercent = tonumber(percent) or 0
    local barPercent = actualPercent

    if barPercent > 100 then
        barPercent = 100
    elseif barPercent < 0 then
        barPercent = 0
    end

    if state == "disabled" then
        usageLabel = "REQUEST DISABLED"
    elseif state == "hold" then
        usageLabel = "REQUEST HOLD"
    end

    local barWidth = 24
    local filledBlocks = math.floor(barPercent / 100 * barWidth)
    if filledBlocks < 0 then
        filledBlocks = 0
    end
    if filledBlocks > barWidth then
        filledBlocks = barWidth
    end

    local fillText = ""
    for i = 1, filledBlocks do
        fillText = fillText .. "█"
    end

    local emptyText = ""
    for i = 1, barWidth - filledBlocks do
        emptyText = emptyText .. "░"
    end

    local lineOne = "┌──────────────────────────────────┐"
    local lineTwo = "│ " .. string.sub(title .. string.rep(" ", 32), 1, 32) .. " │"
    local lineThree = "│ " .. string.sub(subtitle .. string.rep(" ", 32), 1, 32) .. " │"
    local blankLine = "│                                  │"
    local divider = "│   ───────────────────────────   │"
    local inventoryTitle = "│   " .. string.sub("ITEM INVENTORY" .. string.rep(" ", 20), 1, 20) .. " │"
    local inventoryValue = "│   " .. string.sub(formatNumber(count) .. " / " .. formatNumber(total) .. string.rep(" ", 28), 1, 28) .. " │"
    local progressText = "│   " .. string.sub(fillText .. emptyText .. " " .. string.format("%.1f%%", actualPercent) .. string.rep(" ", 30), 1, 30) .. " │"
    local statusText = "│   " .. string.sub(usageLabel .. string.rep(" ", 28), 1, 28) .. " │"
    local thresholdText = "│   < " .. tostring(config.enablePercent) .. "%  ENABLE                 │"
    local disableText = "│   ≥ " .. tostring(config.disablePercent) .. "%  DISABLE                │"
    local lastLine = "└──────────────────────────────────┘"

    local lines = {
        lineOne,
        lineTwo,
        lineThree,
        blankLine,
        divider,
        blankLine,
        inventoryTitle,
        blankLine,
        inventoryValue,
        blankLine,
        progressText,
        blankLine,
        statusText,
        blankLine,
        divider,
        blankLine,
        thresholdText,
        disableText,
        lastLine
    }

    if monitor.setTextScale then
        monitor.setTextScale(0.5)
    end

    local width, height = monitor.getSize()
    if width and height and height >= 20 then

        monitor.clear()
        setMonitorColours(monitor, colors.white, colors.black)

        for i, line in ipairs(lines) do

            if i <= height then
                monitor.setCursorPos(1, i)
                monitor.write(line)
            end
        end
    else

        monitor.clear()
        setMonitorColours(monitor, colors.white, colors.black)
        monitor.setCursorPos(1, 1)
        monitor.write(title)
        monitor.setCursorPos(1, 2)
        monitor.write(subtitle)
        monitor.setCursorPos(1, 3)
        monitor.write(string.format("%s / %s", formatNumber(count), formatNumber(total)))
        monitor.setCursorPos(1, 4)
        monitor.write(string.format("%.1f%%", percent))
        monitor.setCursorPos(1, 5)
        monitor.write(usageLabel)
    end

    if state == "enabled" then
        setMonitorColours(monitor, colors.lime, colors.black)
    elseif state == "disabled" then
        setMonitorColours(monitor, colors.red, colors.black)
    else
        setMonitorColours(monitor, colors.yellow, colors.black)
    end

    monitor.setCursorPos(10, 11)
    monitor.write(fillText)
    monitor.setCursorPos(10, 11)
    monitor.write(fillText .. emptyText)
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