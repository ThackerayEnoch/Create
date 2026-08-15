-- Advanced Train Dispatch - supply/central server.
-- One server controls one supply station/resource pair.

local CONFIG_PATH = "/server_config.lua"
local PROTOCOL_PATH = "/protocol.lua"
local protocol = dofile(PROTOCOL_PATH)

local function clearScreen()
    term.clear(); term.setCursorPos(1, 1)
end

local function ask(prompt, default)
    if default ~= nil then write(prompt .. " [" .. tostring(default) .. "]: ") else write(prompt .. ": ") end
    local v = read()
    if v == "" and default ~= nil then return default end
    return v
end

local function askYesNo(prompt, default)
    while true do
        local v = string.lower(tostring(ask(prompt, default)))
        if v == "y" or v == "yes" then return true end
        if v == "n" or v == "no" then return false end
        print("Please enter y or n.")
    end
end

local function scanStations()
    local out = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "Create_Station" then
            local p = peripheral.wrap(name)
            if p then
                local ok, stationName = pcall(function() return p.getStationName() end)
                if ok then table.insert(out, { peripheralName = name, name = tostring(stationName or ""), peripheral = p }) end
            end
        end
    end
    table.sort(out, function(a,b) return a.peripheralName < b.peripheralName end)
    return out
end

local function selectStation()
    while true do
        clearScreen(); print("=== Supply Station Selection ===\n")
        local list = scanStations()
        for i, x in ipairs(list) do print("["..i.."] "..x.peripheralName.."  "..x.name) end
        if #list == 0 then print("No Create_Station found."); sleep(2) else
            local n = tonumber(ask("Select station"))
            if n and list[n] then return list[n] end
        end
    end
end

local function deviceCapabilities(name)
    local p = peripheral.wrap(name)
    if not p then return nil end
    local itemOK = pcall(function() return p.list() end)
    local fluidOK = pcall(function() return p.tanks() end)
    if itemOK then return "item", p end
    if fluidOK then return "fluid", p end
    return nil
end

local function scanStorage()
    local out = {}
    for _, name in ipairs(peripheral.getNames()) do
        local kind, p = deviceCapabilities(name)
        if kind then table.insert(out, {peripheralName=name, kind=kind, peripheral=p}) end
    end
    table.sort(out, function(a,b) return a.peripheralName < b.peripheralName end)
    return out
end

local function selectStorage()
    while true do
        clearScreen(); print("=== Train Storage / Interface Selection ===\n")
        print("Select the peripheral exposed by the portable storage interface while the train is connected.")
        print("It may expose an item inventory OR a fluid tank interface.\n")
        local list = scanStorage()
        for i, x in ipairs(list) do print("["..i.."] "..x.peripheralName.."  type="..x.kind) end
        if #list == 0 then print("No item/fluid storage peripheral found."); sleep(2) else
            local n = tonumber(ask("Select train container"))
            if n and list[n] then return list[n] end
        end
    end
end

local function scanResourceNames(storage)
    local result = {}
    if storage.kind == "item" then
        local ok, items = pcall(function() return storage.peripheral.list() end)
        if ok and type(items) == "table" then
            local seen = {}
            for _, item in pairs(items) do if item and item.name and not seen[item.name] then seen[item.name]=true; table.insert(result,item.name) end end
        end
    else
        local ok, tanks = pcall(function() return storage.peripheral.tanks() end)
        if ok and type(tanks) == "table" then
            local seen = {}
            for _, tank in pairs(tanks) do if tank and tank.name and not seen[tank.name] then seen[tank.name]=true; table.insert(result,tank.name) end end
        end
    end
    table.sort(result)
    return result
end

local function selectResource(storage)
    local names = scanResourceNames(storage)
    clearScreen(); print("=== Resource Type ===\n")
    print("Resource type is used as the broadcast key and station-name prefix.")
    if #names > 0 then
        for i, name in ipairs(names) do print("["..i.."] "..name) end
        print("[m] manually enter")
        local v = ask("Select resource", "m")
        if v ~= "m" then local n=tonumber(v); if n and names[n] then return names[n] end end
    end
    while true do
        local v = ask("Resource type")
        if v ~= "" then return v end
    end
end

local function saveConfig(c)
    local f=fs.open(CONFIG_PATH,"w"); if not f then error("Cannot write server_config.lua") end
    f.writeLine("return {")
    f.writeLine("  version = 1,")
    f.writeLine("  stationPeripheral = "..string.format("%q",c.stationPeripheral)..",")
    f.writeLine("  stationName = "..string.format("%q",c.stationName)..",")
    f.writeLine("  factoryId = "..string.format("%q",c.factoryId)..",")
    f.writeLine("  resourceType = "..string.format("%q",c.resourceType)..",")
    f.writeLine("  resourceKind = "..string.format("%q",c.resourceKind)..",")
    f.writeLine("  trainStoragePeripheral = "..string.format("%q",c.trainStoragePeripheral))
    f.writeLine("}"); f.close()
end

local function loadConfig()
    if not fs.exists(CONFIG_PATH) then return nil end
    local ok,c=pcall(dofile,CONFIG_PATH); if ok and type(c)=="table" then return c end
    return nil
end

local function installServer()
    local station=selectStation()
    local storage=selectStorage()
    local resource=selectResource(storage)
    clearScreen(); print("=== Supply Server Setup ===\n")
    local factoryId=ask("Factory identifier","Factory")
    local requestName=resource.."_Request_"..factoryId
    local supplyName=resource.."_Supply"
    print("\nRequest name: "..requestName)
    print("Supply name:  "..supplyName)
    if not askYesNo("Write server configuration?","y") then return end
    saveConfig({stationPeripheral=station.peripheralName,stationName=station.name,factoryId=factoryId,resourceType=resource,resourceKind=storage.kind,trainStoragePeripheral=storage.peripheralName})
    if fs.exists("/disk/server.lua") then fs.copy("/disk/server.lua","/server.lua") end
    if fs.exists("/disk/protocol.lua") then fs.copy("/disk/protocol.lua","/protocol.lua") end
    print("Server installed.")
    print("Bind the portable storage interface and keep it connected to the computer network.")
end

local args = {...}
local config=loadConfig()
if args[1] == "install" then
    installServer()
    config=loadConfig()
elseif not config then
    installServer()
    config=loadConfig()
end
if not config then error("No server configuration") end

local function modem()
    for _,n in ipairs(peripheral.getNames()) do if peripheral.getType(n)=="modem" then return n end end
end
local modemSide=modem()
if not modemSide then error("No modem found") end
if not rednet.isOpen(modemSide) then rednet.open(modemSide) end

local station=peripheral.wrap(config.stationPeripheral)
if not station then error("Supply station peripheral not found: "..tostring(config.stationPeripheral)) end
local storage=peripheral.wrap(config.trainStoragePeripheral)
local requestName=config.resourceType.."_Request_"..config.factoryId
local supplyName=config.resourceType.."_Supply"
local paused=false
local noResource=false
local noRequestSince=os.clock()

local function setName(name)
    pcall(function() station.setStationName(name) end)
end
local function broadcast(t)
    rednet.broadcast({protocol=protocol.PROTOCOL,type=t,resourceType=config.resourceType},protocol.PROTOCOL)
end
local function isFull()
    if not storage then return false end
    if config.resourceKind=="fluid" then
        local ok,tanks=pcall(function() return storage.tanks() end); if not ok then return false end
        local amount=0; local capacity=0
        for _,t in pairs(tanks) do capacity=capacity+(t.capacity or 0); if t and t.name==config.resourceType then amount=amount+(t.amount or 0) end end
        return capacity>0 and amount>=capacity
    end
    local ok,size=pcall(function() return storage.size() end)
    if not ok or not size or size<=0 then return false end
    local ok2,items=pcall(function() return storage.list() end); if not ok2 then return false end
    local used=0; local resourceCount=0
    for _,i in pairs(items) do used=used+1; if i and i.name==config.resourceType then resourceCount=resourceCount+(i.count or 0) end end
    return used>=size and resourceCount>0
end

setName(requestName)
print("Advanced Train Supply Server")
print("Resource: "..config.resourceType)
print("Station:  "..requestName)

while true do
    local sender,message=rednet.receive(protocol.PROTOCOL,1)
    if type(message)=="table" then
        if message.type==protocol.HELLO then
            rednet.send(sender,{protocol=protocol.PROTOCOL,type=protocol.ANSWER,resourceType=config.resourceType},protocol.PROTOCOL)
        elseif message.resourceType==config.resourceType and message.type==protocol.REQUEST_RENAME then
            noRequestSince=os.clock()
            if noResource then
                paused=true
                broadcast(protocol.PAUSE)
                setName(requestName)
            else
                paused=false
                rednet.broadcast({protocol=protocol.PROTOCOL,type=protocol.ALLOW_RENAME,resourceType=config.resourceType},protocol.PROTOCOL)
                setName(supplyName)
            end
        elseif message.resourceType==config.resourceType and message.type==protocol.NO_RESOURCE then
            noResource=true
            paused=true
            broadcast(protocol.PAUSE)
            setName(requestName)
        end
    end

    if isFull() then
        noResource=false
        paused=false
        setName(supplyName)
        broadcast(protocol.ENABLE)
    end

    if os.clock()-noRequestSince>=60 then
        setName(requestName)
        noRequestSince=os.clock()
    end
end
