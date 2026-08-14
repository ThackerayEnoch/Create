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


local function prettyItemName(rawName)
    local item = tostring(rawName or "item")
    item = item:gsub("^.-:", "")
    item = item:gsub("_", " ")
    item = item:gsub("%s+", " ")
    item = item:gsub("^%s*(.-)%s*$", "%1")

    local output = ""

    for part in item:gmatch("%S+") do
        if output ~= "" then
            output = output .. " "
        end
        output = output .. string.upper(part)
    end

    if output == "" then
        return "ITEM REQUEST"
    end

    return output
end


local function prettyStationName(rawName)
    local name = tostring(rawName or "Station")
    name = name:gsub("^.-_", "")
    name = name:gsub("_", " ")
    name = name:gsub("%s+", " ")
    name = name:gsub("^%s*(.-)%s*$", "%1")

    local output = ""

    for part in name:gmatch("%S+") do
        if output ~= "" then
            output = output .. " "
        end
        output = output .. string.upper(part)
    end

    if output == "" then
        return "FACTORY REQUEST"
    end

    return output
end


local function centerText(monitor, y, text, colour)
    local width = select(1, monitor.getSize())
    local value = tostring(text or "")

    if #value > width then
        value = value:sub(1, width)
    end

    local x = math.max(1, math.floor((width - #value) / 2) + 1)

    setMonitorColours(
        monitor,
        colour or colors.white,
        colors.black
    )

    monitor.setCursorPos(x, y)
    monitor.write(value)
end


local function drawHorizontalLine(monitor, y, colour)
    local width = select(1, monitor.getSize())

    setMonitorColours(
        monitor,
        colour or colors.blue,
        colors.black
    )

    monitor.setCursorPos(1, y)
    monitor.write(string.rep("=", width))
end


local function drawProgressBar(monitor, x, y, width, percent)
    local clamped = tonumber(percent) or 0

    if clamped < 0 then
        clamped = 0
    elseif clamped > 100 then
        clamped = 100
    end

    local filled = math.floor(width * clamped / 100)

    -- Background bar
    paintutils.drawFilledBox(
        x,
        y,
        x + width - 1,
        y + 1,
        colors.gray
    )

    -- Filled bar
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

    -- Percentage
    local percentText =
        string.format("%.1f%%", clamped)

    setMonitorColours(
        monitor,
        colors.white,
        colors.black
    )

    monitor.setCursorPos(
        x + width + 2,
        y
    )

    monitor.write(percentText)
end


local function drawStatusBox(
    monitor,
    x,
    y,
    width,
    height,
    state
)
    local borderColour = colors.lime
    local statusColour = colors.lime
    local statusText = "REQUEST ENABLED"

    if state == "disabled" then
        borderColour = colors.red
        statusColour = colors.red
        statusText = "REQUEST DISABLED"
    elseif state == "hold" then
        borderColour = colors.yellow
        statusColour = colors.yellow
        statusText = "REQUEST HOLD"
    end

    -- Outer box
    paintutils.drawBox(
        x,
        y,
        x + width - 1,
        y + height - 1,
        borderColour
    )

    -- Status marker
    paintutils.drawFilledBox(
        x + 2,
        y + 2,
        x + 3,
        y + height - 3,
        statusColour
    )

    -- Status text
    local statusX =
        x + 6

    setMonitorColours(
        monitor,
        statusColour,
        colors.black
    )

    monitor.setCursorPos(
        statusX,
        y + math.floor(height / 2)
    )

    monitor.write(statusText)
end


local function drawMonitorStatus(
    monitor,
    count,
    total,
    percent,
    state
)
    if not monitor then
        return
    end

    -- Use the drawing API rather than Unicode box-drawing characters.
    local width, height = monitor.getSize()

    monitor.setTextScale(0.5)
    monitor.clear()

    setMonitorColours(
        monitor,
        colors.white,
        colors.black
    )

    -- The compact layout is intended for a monitor of at least 32x16.
    if width < 32 or height < 16 then
        centerText(
            monitor,
            1,
            "FACTORY REQUEST",
            colors.white
        )

        centerText(
            monitor,
            2,
            prettyItemName(config.item),
            colors.cyan
        )

        monitor.setCursorPos(2, 4)
        monitor.write(
            formatNumber(count)
            .. " / "
            .. formatNumber(total)
        )

        drawProgressBar(
            monitor,
            2,
            6,
            math.max(12, width - 12),
            percent
        )

        local status =
            state == "enabled"
            and "ONLINE"
            or state == "disabled"
            and "OFFLINE"
            or "HOLD"

        centerText(
            monitor,
            9,
            status,
            state == "enabled"
                and colors.lime
                or state == "disabled"
                and colors.red
                or colors.yellow
        )

        centerText(
            monitor,
            11,
            "< "
            .. tostring(config.enablePercent)
            .. "% ENABLE",
            colors.lime
        )

        centerText(
            monitor,
            12,
            ">= "
            .. tostring(config.disablePercent)
            .. "% DISABLE",
            colors.red
        )

        return
    end

    -- Main title
    centerText(
        monitor,
        2,
        prettyItemName(config.item),
        colors.white
    )

    centerText(
        monitor,
        3,
        prettyStationName(config.stationName),
        colors.yellow
    )

    drawHorizontalLine(
        monitor,
        5,
        colors.blue
    )

    -- Inventory title
    monitor.setCursorPos(4, 7)
    setMonitorColours(
        monitor,
        colors.cyan,
        colors.black
    )
    monitor.write("ITEM INVENTORY")

    -- Current / capacity
    monitor.setCursorPos(4, 9)
    setMonitorColours(
        monitor,
        colors.white,
        colors.black
    )

    monitor.write(
        formatNumber(count)
        .. " / "
        .. formatNumber(total)
    )

    -- Progress bar
    local barWidth =
        math.min(
            math.max(12, width - 20),
            28
        )

    local barX = 4
    local barY = 11

    drawProgressBar(
        monitor,
        barX,
        barY,
        barWidth,
        percent
    )

    -- Status box
    local boxY = math.min(14, height - 5)
    local boxHeight = 3
    local boxWidth = math.min(
        width - 6,
        32
    )

    drawStatusBox(
        monitor,
        3,
        boxY,
        boxWidth,
        boxHeight,
        state
    )

    -- Bottom divider
    local dividerY =
        math.min(
            height - 3,
            boxY + boxHeight + 1
        )

    drawHorizontalLine(
        monitor,
        dividerY,
        colors.blue
    )

    -- Thresholds
    setMonitorColours(
        monitor,
        colors.lime,
        colors.black
    )

    monitor.setCursorPos(
        4,
        dividerY + 2
    )

    monitor.write(
        "< "
        .. tostring(config.enablePercent)
        .. "% ENABLE"
    )

    setMonitorColours(
        monitor,
        colors.red,
        colors.black
    )

    monitor.setCursorPos(
        4,
        dividerY + 3
    )

    monitor.write(
        ">= "
        .. tostring(config.disablePercent)
        .. "% DISABLE"
    )
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