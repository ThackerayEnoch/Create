--[[
    Create Train Station Unloading Controller
    Installation Program

    Current design:

    One Computer
        ↓
    A factory Wired Modem network
        ↓
    One Train Station
        ↓
    One inventory device

    The installer is responsible for:
        1. Scanning for Create_Station devices
        2. The player selecting the physical station
        3. The player entering the formal station name
        4. Checking for station name conflicts
        5. Setting the station name
        6. Scanning for inventory devices
        7. The player selecting the inventory
        8. Configuring the item and capacity
        9. Configuring the 20% / 80% thresholds
        10. Generating config.lua
        11. Installing station.lua
        12. Creating startup.lua
]]

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

        if number then

            if (min == nil or number >= min)
                and (max == nil or number <= max) then

                return number

            end

        end

        print("Invalid input, please try again.")
    end
end


local function askYesNo(prompt, default)

    while true do

        local value =
            ask(prompt, default)

        value =
            string.lower(
                tostring(value)
            )

        if value == "y"
            or value == "yes" then

            return true

        end

        if value == "n"
            or value == "no" then

            return false

        end

        print("Please enter y or n.")
    end
end


--------------------------------------------------
-- Find Create Station
--------------------------------------------------

local function scanStations()

    local stations = {}

    for _, peripheralName
        in ipairs(peripheral.getNames()) do

        local peripheralType =
            peripheral.getType(
                peripheralName
            )

        if peripheralType == "Create_Station" then

            local station =
                peripheral.wrap(
                    peripheralName
                )

            if station then

                local ok, stationName =
                    pcall(function()
                        return station.getStationName()
                    end)

                if ok then

                    table.insert(
                        stations,
                        {
                            peripheralName =
                                peripheralName,

                            stationName =
                                stationName,

                            peripheral =
                                station
                        }
                    )

                end
            end
        end
    end

    return stations
end


--------------------------------------------------
-- Select Train Station
--------------------------------------------------

local function selectStation()

    while true do

        local stations =
            scanStations()

        clearScreen()

        print("========================================")
        print("        Train Station Selection")
        print("================================")
        print()

        if #stations == 0 then

            print("No Create Train Station found.")
            print()
            print("Please check:")
            print("1. The Wired Modem is connected")
            print("2. The Train Station is connected to the network")
            print("3. CC:Tweaked can detect the station")
            print()

            pause()

        else

            for i, station
                in ipairs(stations) do

                print(
                    "[" .. i .. "] "
                    .. station.peripheralName
                )

                print(
                    "    Current name: "
                    .. tostring(
                        station.stationName
                    )
                )

                print()

            end

            local choice =
                tonumber(
                    ask("Please select a station")
                )

            if choice
                and stations[choice] then

                return stations[choice]
            end

            print()
            print("Invalid selection.")
            sleep(1)

        end
    end
end


--------------------------------------------------
-- Check whether the station name already exists
--------------------------------------------------

local function stationNameExists(
    targetName,
    selectedPeripheralName
)

    local stations =
        scanStations()

    for _, station
        in ipairs(stations) do

        if station.peripheralName
            ~= selectedPeripheralName then

            if station.stationName
                == targetName then

                return true,
                    station.peripheralName

            end
        end
    end

    return false, nil
end


--------------------------------------------------
-- Let the player set the station name
--------------------------------------------------

local function configureStationName(
    selectedStation
)

    while true do

        clearScreen()

        print("========================================")
        print("        Station Name Setup")
        print("================================")
        print()

        print(
            "Physical device: "
            .. selectedStation.peripheralName
        )

        print(
            "Current name: "
            .. tostring(
                selectedStation.stationName
            )
        )

        print()

        print("Please enter the official station name.")
        print()
        print("Example:")
        print("IronBlock_Request_Andesite_Alloy_Line")
        print()

        local stationName =
            ask(
                "Station name"
            )

        if stationName == "" then

            print()
            print("Station name cannot be empty.")
            pause()

        else

            --------------------------------------------------
            -- Check for name conflicts
            --------------------------------------------------

            local exists,
                conflictPeripheral =
                stationNameExists(
                    stationName,
                    selectedStation.peripheralName
                )

            if exists then

                print()
                print("================================")
                print("Name conflict!")
                print("================================")
                print()

                print(
                    "This name is already used by another station:"
                )

                print(
                    stationName
                )

                print()

                print(
                    "Conflicting device: "
                    .. tostring(
                        conflictPeripheral
                    )
                )

                pause()

            else

                --------------------------------------------------
                -- Generate the disabled name
                --------------------------------------------------

                local disabledName =
                    ask(
                        "Disabled name",
                        "DISABLED_" .. stationName
                    )

                if disabledName == "" then

                    print(
                        "Disabled name cannot be empty."
                    )

                    pause()

                else

                    --------------------------------------------------
                    -- Check for disabled-name conflict
                    --------------------------------------------------

                    local disabledExists,
                        disabledConflict =
                        stationNameExists(
                            disabledName,
                            selectedStation.peripheralName
                        )

                    if disabledExists then

                        print()
                        print(
                            "The disabled name is already in use:"
                        )

                        print(
                            disabledName
                        )

                        print(
                            "Conflicting device: "
                            .. tostring(
                                disabledConflict
                            )
                        )

                        pause()

                    else

                        return {
                            stationName =
                                stationName,

                            disabledName =
                                disabledName
                        }

                    end
                end
            end
        end
    end
end


--------------------------------------------------
-- Check whether the device supports the inventory interface
--------------------------------------------------

local function getInventoryInfo(
    peripheralName
)

    local device =
        peripheral.wrap(
            peripheralName
        )

    if not device then
        return nil
    end


    --------------------------------------------------
    -- Test list()
    --------------------------------------------------

    local ok, result =
        pcall(function()

            return device.list()

        end)


    if not ok then
        return nil
    end


    if type(result) ~= "table" then
        return nil
    end


    return {
        peripheralName =
            peripheralName,

        peripheralType =
            peripheral.getType(
                peripheralName
            ),

        peripheral =
            device
    }
end


--------------------------------------------------
-- Scan inventory devices
--------------------------------------------------

local function scanInventories()

    local inventories = {}

    for _, peripheralName
        in ipairs(peripheral.getNames()) do

        local info =
            getInventoryInfo(
                peripheralName
            )

        if info then

            table.insert(
                inventories,
                info
            )

        end
    end

    return inventories
end


--------------------------------------------------
-- Get inventory items
--------------------------------------------------

local function getInventoryItems(
    inventory
)

    local ok, result =
        pcall(function()

            return inventory.list()

        end)


    if not ok then
        return nil
    end


    return result
end


--------------------------------------------------
-- Display inventory
--------------------------------------------------

local function showInventory(
    inventory
)

    local items =
        getInventoryItems(
            inventory.peripheral
        )

    print()
    print("----------------------------------------")
    print("Current inventory")
    print("----------------------------------------")

    if not items then

        print("Unable to read inventory.")

        return
    end


    local count = 0


    for slot, item
        in pairs(items) do

        count = count + 1

        print(
            "Slot "
            .. tostring(slot)
            .. " : "
            .. tostring(item.name)
            .. " x"
            .. tostring(item.count)
        )

        --------------------------------------------------
        -- Show at most 20 items
        --------------------------------------------------

        if count >= 20 then

            print("...")

            break
        end
    end


    if count == 0 then

        print("(Inventory is empty)")

    end


    print("----------------------------------------")
end


--------------------------------------------------
-- Select inventory
--------------------------------------------------

local function selectInventory()

    while true do

        local inventories =
            scanInventories()

        clearScreen()

        print("========================================")
        print("        Inventory Device Selection")
        print("================================")
        print()

        if #inventories == 0 then

            print("No readable inventory device found.")
            print()

            print("The program requires the device to support:")
            print("    inventory.list()")
            print()

            pause()

        else

            for i, inventory
                in ipairs(inventories) do

                print(
                    "[" .. i .. "] "
                    .. inventory.peripheralName
                )

                print(
                    "    Type: "
                    .. tostring(
                        inventory.peripheralType
                    )
                )

                print()

            end


            local choice =
                tonumber(
                    ask("Please select an inventory")
                )


            if choice
                and inventories[choice] then

                local selected =
                    inventories[choice]


                showInventory(
                    selected
                )


                print()

                local confirm =
                    askYesNo(
                        "Use this inventory?",
                        "y"
                    )


                if confirm then

                    return selected

                end

            else

                print()
                print("Invalid selection.")
                sleep(1)

            end
        end
    end
end


--------------------------------------------------
-- Write config.lua
--------------------------------------------------

local function writeConfig(
    config
)

    local file =
        fs.open(
            "config.lua",
            "w"
        )

    if not file then

        error(
            "Unable to create config.lua"
        )
    end


    file.writeLine(
        "return {"
    )


    file.writeLine(
        "    stationName = "
        .. string.format(
            "%q",
            config.stationName
        )
        .. ","
    )


    file.writeLine(
        "    disabledName = "
        .. string.format(
            "%q",
            config.disabledName
        )
        .. ","
    )


    file.writeLine(
        "    inventoryPeripheral = "
        .. string.format(
            "%q",
            config.inventoryPeripheral
        )
        .. ","
    )


    file.writeLine(
        "    inventoryType = "
        .. string.format(
            "%q",
            config.inventoryType
        )
        .. ","
    )


    file.writeLine(
        "    item = "
        .. string.format(
            "%q",
            config.item
        )
        .. ","
    )


    file.writeLine(
        "    capacity = "
        .. tostring(
            config.capacity
        )
        .. ","
    )


    file.writeLine(
        "    enablePercent = "
        .. tostring(
            config.enablePercent
        )
        .. ","
    )


    file.writeLine(
        "    disablePercent = "
        .. tostring(
            config.disablePercent
        )
        .. ","
    )


    file.writeLine(
        "    checkInterval = 5"
    )


    file.writeLine(
        "}"
    )


    file.close()
end


--------------------------------------------------
-- Install station.lua
--------------------------------------------------

local function installStationProgram()

    if not fs.exists(
        "/disk/station.lua"
    ) then

        error(
            "station.lua is missing from the disk"
        )
    end


    --------------------------------------------------
    -- Remove previous program
    --------------------------------------------------

    if fs.exists(
        "/station.lua"
    ) then

        fs.delete(
            "/station.lua"
        )
    end


    --------------------------------------------------
    -- Copy from disk
    --------------------------------------------------

    fs.copy(
        "/disk/station.lua",
        "/station.lua"
    )

end


--------------------------------------------------
-- Create startup.lua
--------------------------------------------------

local function createStartup()

    local file =
        fs.open(
            "/startup.lua",
            "w"
        )

    if not file then

        error(
            "Unable to create startup.lua"
        )
    end


    file.writeLine(
        'shell.run("station.lua")'
    )


    file.close()
end


--------------------------------------------------
-- Main program
--------------------------------------------------

clearScreen()

print("========================================")
print(" Create Station Controller")
print(" Installation Program")
print("========================================")
print()

print("This program will configure a train unloading request station.")
print()

pause()


--------------------------------------------------
-- STEP 1
--------------------------------------------------

clearScreen()

print("========================================")
print(" Step 1 / 5")
print(" Select the physical Train Station")
print("========================================")
print()

local selectedStation =
    selectStation()


if not selectedStation then

    print("No station selected.")

    return
end


--------------------------------------------------
-- STEP 2
--------------------------------------------------

local stationConfig =
    configureStationName(
        selectedStation
    )


--------------------------------------------------
-- STEP 3
--------------------------------------------------

clearScreen()

print("========================================")
print(" Step 3 / 5")
print(" Select inventory device")
print("========================================")
print()

local selectedInventory =
    selectInventory()


if not selectedInventory then

    print("No inventory selected.")

    return
end


--------------------------------------------------
-- STEP 4
--------------------------------------------------

clearScreen()

print("========================================")
print(" Step 4 / 5")
print(" Item and capacity")
print("========================================")
print()


local item =
    ask(
        "Requested item ID",
        "minecraft:iron_ingot"
    )


while item == "" do

    print(
        "Item ID cannot be empty."
    )

    item =
        ask(
            "Requested item ID"
        )
end


local capacity =
    askNumber(
        "Total inventory capacity",
        4096,
        1
    )


--------------------------------------------------
-- STEP 5
--------------------------------------------------

clearScreen()

print("========================================")
print(" Step 5 / 5")
print(" Threshold settings")
print("========================================")
print()


local enablePercent =
    askNumber(
        "Entry allowed threshold (%)",
        20,
        0,
        100
    )


local disablePercent =
    askNumber(
        "Entry blocked threshold (%)",
        80,
        0,
        100
    )


--------------------------------------------------
-- Check thresholds
--------------------------------------------------

if enablePercent >= disablePercent then

    print()
    print("Error:")
    print("The allow-entry threshold must be lower than the deny-entry threshold.")
    print()

    print(
        "Example: 20% / 80%"
    )

    pause()

    return
end


--------------------------------------------------
-- Final configuration
--------------------------------------------------

local config = {

    stationName =
        stationConfig.stationName,

    disabledName =
        stationConfig.disabledName,

    inventoryPeripheral =
        selectedInventory.peripheralName,

    inventoryType =
        selectedInventory.peripheralType,

    item =
        item,

    capacity =
        capacity,

    enablePercent =
        enablePercent,

    disablePercent =
        disablePercent
}


--------------------------------------------------
-- Show final configuration
--------------------------------------------------

clearScreen()

print("========================================")
print("          Installation Confirmation")
print("========================================")
print()

print(
    "Station name:"
)

print(
    "  "
    .. config.stationName
)

print()

print(
    "Disabled name:"
)

print(
    "  "
    .. config.disabledName
)

print()

print(
    "Inventory device:"
)

print(
    "  "
    .. config.inventoryPeripheral
)

print()

print(
    "Inventory type:"
)

print(
    "  "
    .. config.inventoryType
)

print()

print(
    "Requested item:"
)

print(
    "  "
    .. config.item
)

print()

print(
    "Inventory capacity:"
)

print(
    "  "
    .. tostring(
        config.capacity
    )
)

print()

print(
    "Allow entry:"
)

print(
    "  < "
    .. tostring(
        config.enablePercent
    )
    .. "%"
)

print()

print(
    "Block entry:"
)

print(
    "  >= "
    .. tostring(
        config.disablePercent
    )
    .. "%"
)

print()

print("========================================")
print()


local confirm =
    askYesNo(
        "Confirm installation?",
        "y"
    )


if not confirm then

    print()
    print("Installation cancelled.")

    return
end


--------------------------------------------------
-- Start installation
--------------------------------------------------

clearScreen()

print("========================================")
print("          Installing")
print("========================================")
print()


--------------------------------------------------
-- 1. Set station name
--------------------------------------------------

print(
    "[1/4] Setting station name..."
)


local ok, err =
    pcall(function()

        selectedStation.peripheral
            .setStationName(
                config.stationName
            )

    end)


if not ok then

    print()
    print(
        "Failed to set station name:"
    )

    print(
        tostring(err)
    )

    return
end


print("      OK")


--------------------------------------------------
-- 2. Write config.lua
--------------------------------------------------

print(
    "[2/4] Creating config.lua..."
)


local okConfig, errConfig =
    pcall(function()

        writeConfig(
            config
        )

    end)


if not okConfig then

    print()
    print(
        "Failed to create config.lua:"
    )

    print(
        tostring(errConfig)
    )

    return
end


print("      OK")


--------------------------------------------------
-- 3. Install station.lua
--------------------------------------------------

print(
    "[3/4] Installing station.lua..."
)


local okStation, errStation =
    pcall(function()

        installStationProgram()

    end)


if not okStation then

    print()
    print(
        "Failed to install station.lua:"
    )

    print(
        tostring(errStation)
    )

    return
end


print("      OK")


--------------------------------------------------
-- 4. Create startup.lua
--------------------------------------------------

print(
    "[4/4] Creating startup.lua..."
)


local okStartup, errStartup =
    pcall(function()

        createStartup()

    end)


if not okStartup then

    print()
    print(
        "Failed to create startup.lua:"
    )

    print(
        tostring(errStartup)
    )

    return
end


print("      OK")


--------------------------------------------------
-- Installation complete
--------------------------------------------------

print()
print("========================================")
print("          Installation Complete")
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

print(
    "Below "
    .. tostring(config.enablePercent)
    .. "%: allow entry"
)

print(
    "At "
    .. tostring(config.disablePercent)
    .. "%: block entry"
)

print()

print("Generated:")
print("  config.lua")
print("  station.lua")
print("  startup.lua")

print()


--------------------------------------------------
-- Restart?
--------------------------------------------------

local reboot =
    askYesNo(
        "Restart the computer now?",
        "y"
    )


if reboot then

    os.reboot()

else

    print()
    print(
        "Installation complete. Enter reboot to start the control program."
    )

end