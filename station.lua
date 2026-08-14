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