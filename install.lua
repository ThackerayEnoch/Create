local function ask(prompt, default)

    if default then
        write(prompt .. " [" .. default .. "]: ")
    else
        write(prompt .. ": ")
    end

    local value = read()

    if value == "" and default then
        return default
    end

    return value
end


print("========================================")
print("     Create 火车需求站控制器")
print("              安装程序")
print("========================================")
print()

print("欢迎使用火车需求站控制器安装程序！")
print("请按照提示输入本站的配置信息。")
print()
local stationName = ask(
    "请输入车站名称",
    "铁板需求A"
)



local disabledName = ask(
    "请输入禁用后的车站名称",
    "DISABLED-" .. stationName
)




local item = ask(
    "请输入需要检测的物品 ID",
    "minecraft:iron_ingot"
)



local capacity = tonumber(
    ask(
        "请输入容器容量",
        "4096"
    )
)

while not capacity or capacity <= 0 do

    print()
    print("错误：容量必须是大于 0 的数字！")
    print()

    capacity = tonumber(
        ask(
            "请重新输入容器容量",
            "4096"
        )
    )

end



local enablePercent = tonumber(
    ask(
        "请输入开启车站的库存百分比",
        "20"
    )
)

while not enablePercent
    or enablePercent < 0
    or enablePercent > 100 do

    print()
    print("错误：百分比必须在 0～100 之间！")
    print()

    enablePercent = tonumber(
        ask(
            "请重新输入开启阈值",
            "20"
        )
    )

end



local disablePercent = tonumber(
    ask(
        "请输入禁用车站的库存百分比",
        "80"
    )
)

while not disablePercent
    or disablePercent < 0
    or disablePercent > 100 do

    print()
    print("错误：百分比必须在 0～100 之间！")
    print()

    disablePercent = tonumber(
        ask(
            "请重新输入禁用阈值",
            "80"
        )
    )

end



if enablePercent >= disablePercent then

    print()
    print("========================================")
    print("错误：")
    print("开启阈值必须小于禁用阈值！")
    print()
    print("例如：")
    print("开启阈值：20")
    print("禁用阈值：80")
    print("========================================")

    return

end



print()
print("========================================")
print("              配置确认")
print("========================================")

print("车站名称       ：" .. stationName)
print("禁用后名称     ：" .. disabledName)
print("检测物品       ：" .. item)
print("容器容量       ：" .. capacity)
print("开启阈值       ：" .. enablePercent .. "%")
print("禁用阈值       ：" .. disablePercent .. "%")

print("========================================")
print()

print("工作逻辑：")
print("库存 < " .. enablePercent .. "%  → 开放车站")
print("库存 >= " .. disablePercent .. "% → 禁用车站")
print(
    enablePercent
    .. "% ～ "
    .. disablePercent
    .. "% → 保持当前状态"
)

print()

--------------------------------------------------
-- 确认
--------------------------------------------------

local confirm = ask(
    "确认安装吗？(y/n)",
    "y"
)

if string.lower(confirm) ~= "y" then

    print()
    print("已取消安装。")
    return

end


print()
print("========================================")
print("              开始安装")
print("========================================")
print()


--------------------------------------------------
-- 创建 config.lua
--------------------------------------------------

print("正在生成配置文件...")

local configFile = fs.open(
    "config.lua",
    "w"
)

configFile.write("return {\n")

configFile.write(
    "    stationName = "
    .. string.format("%q", stationName)
    .. ",\n"
)

configFile.write(
    "    disabledName = "
    .. string.format("%q", disabledName)
    .. ",\n"
)

configFile.write(
    "    item = "
    .. string.format("%q", item)
    .. ",\n"
)

configFile.write(
    "    capacity = "
    .. capacity
    .. ",\n"
)

configFile.write(
    "    enablePercent = "
    .. enablePercent
    .. ",\n"
)

configFile.write(
    "    disablePercent = "
    .. disablePercent
    .. "\n"
)

configFile.write("}\n")

configFile.close()

print("✓ 配置文件生成成功")
print()


print("正在复制控制程序...")

if not fs.exists("/disk/station.lua") then

    print()
    print("错误：")
    print("软盘中没有找到 station.lua！")
    print()
    print("请确认：")
    print("1. 软盘已经插入")
    print("2. station.lua 已经写入软盘")
    print()

    return

end


if fs.exists("station.lua") then
    fs.delete("station.lua")
end


fs.copy(
    "/disk/station.lua",
    "station.lua"
)

print("✓ 控制程序复制成功")
print()



print("正在设置开机启动...")

local startupFile = fs.open(
    "startup.lua",
    "w"
)

startupFile.write(
    'shell.run("station.lua")\n'
)

startupFile.close()

print("✓ 开机启动设置成功")
print()


print("========================================")
print("             安装完成！")
print("========================================")
print()

print("车站名称：")
print("  " .. stationName)

print()

print("检测物品：")
print("  " .. item)

print()

print("库存控制：")
print(
    "  < "
    .. enablePercent
    .. "% → 开放"
)

print(
    "  >= "
    .. disablePercent
    .. "% → 禁用"
)
print()
print("已安装文件：")
print("  station.lua")
print("  config.lua")
print("  startup.lua")
print()
print("电脑重启后将自动运行控制程序。")
print()

local reboot = ask(
    "现在重启电脑吗？(y/n)",
    "y"
)

if string.lower(reboot) == "y" then

    print()
    print("正在重启...")
    sleep(2)

    os.reboot()

else

    print()
    print("安装程序结束。")
    print("你可以输入 reboot 手动重启。")

end