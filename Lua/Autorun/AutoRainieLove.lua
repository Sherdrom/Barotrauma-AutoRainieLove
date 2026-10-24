local musicPath = ... .. "/Sounds/last_survivor.ogg"
local hookName = "AutoRainieLove"
local messageName = "AutoRainieLove.Music"

if SERVER then
    local armed, played, active = false, false, false
    local nextCheck = 0

    local function broadcast(start)
        local message = Networking.Start(messageName)
        message.WriteBoolean(start)
        Networking.Send(message, nil, DeliveryMethod.Reliable)
        active = start
    end

    local function reset()
        if active then broadcast(false) end
        armed, played = false, false
        nextCheck = 0
    end

    Hook.Add("roundStart", hookName, reset)
    Hook.Add("roundEnd", hookName, reset)
    Hook.Add("stop", hookName, reset)
    Hook.Add("think", hookName, function()
        if not Game.RoundStarted then
            reset()
            return
        end
        local now = Timer.GetTime()
        if now < nextCheck then return end
        nextCheck = now + 0.25

        local alive = 0
        for character in Character.CharacterList do
            if not character.Removed and character.IsHuman and not character.IsDead
                and (character.TeamID == CharacterTeamType.Team1
                    or character.TeamID == CharacterTeamType.Team2) then
                alive = alive + 1
            end
        end
        if alive > 1 then armed = true end
        if alive ~= 1 then
            if active then broadcast(false) end
        elseif armed and not played then
            played = true
            broadcast(true)
        end
    end)
    return
end

local roster = {}
local team, listener, sound, channel
local armed, played, warned = false, false, false
local nextCheck = 0
local musicCategory = Identifier("music")
local soundManagerType = LuaUserData.CreateStatic("Barotrauma.Sounds.SoundManager")
local pools = LuaUserData.CreateEnumTable("Barotrauma.Sounds.SoundManager+SourcePoolIndex")
LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.SoundPlayer"], "musicChannel")

local function stopOtherMusic()
    -- 原版的噪声音乐层使用 default 分类，因此也要清理原版音乐数组。
    for _, other in pairs(SoundPlayer.musicChannel) do
        if other then other.Dispose() end
    end
    -- shortcut: 其他模组须使用 music 分类，未分类的音乐需要单独适配。
    for _, pool in ipairs({ pools.Default, pools.Voice }) do
        for index = 0, soundManagerType.SourceCount - 1 do
            local other = Game.SoundManager.GetSoundChannelFromIndex(pool, index)
            if other and other ~= channel and other.Category == musicCategory then
                other.Dispose()
            end
        end
    end
end

Hook.Patch(hookName, "Barotrauma.SoundPlayer", "UpdateMusic", { "System.Single" }, function(_, parameters)
    if channel and channel.IsPlaying then parameters.PreventExecution = true end
end, Hook.HookMethodType.Before)

local function stopMusic()
    if channel then channel.Dispose() end
    if sound then sound.Dispose() end
    channel, sound = nil, nil
end

local function reset()
    stopMusic()
    roster = {}
    team, listener = nil, nil
    armed, played = false, false
    nextCheck = 0
end

local function playMusic()
    played = true
    if not File.Exists(musicPath) then
        if not warned then
            print("[AutoRainieLove] 请放入 Ogg Vorbis 音乐：" .. musicPath)
            warned = true
        end
        return
    end

    local ok, err = pcall(function()
        sound = Game.SoundManager.LoadSound(musicPath, true)
        if not sound then error("音频设备不可用") end
        stopOtherMusic()
        channel = sound.Play(1, musicCategory)
        if not channel then error("无法创建音乐播放通道") end
        channel.Looping = true
        channel.MuteBackgroundMusic = true
    end)
    if not ok then
        stopMusic()
        print("[AutoRainieLove] 音乐播放失败：" .. tostring(err))
    end
end

Hook.Add("roundStart", hookName, reset)
Hook.Add("roundEnd", hookName, reset)
Hook.Add("stop", hookName, function()
    reset()
    Hook.RemovePatch(hookName, "Barotrauma.SoundPlayer", "UpdateMusic", { "System.Single" }, Hook.HookMethodType.Before)
end)

Networking.Receive(messageName, function(message)
    if not Game.IsMultiplayer or not Game.RoundStarted then return end
    if message.ReadBoolean() then
        if not played then playMusic() end
    else
        stopMusic()
    end
end)

Hook.Add("character.death", hookName, function(character)
    if roster[character] ~= nil then roster[character] = true end
end)

Hook.Add("think", hookName, function()
    if not Game.RoundStarted then
        if team ~= nil or played then reset() end
        return
    end
    if channel then
        if channel.IsPlaying then stopOtherMusic() else stopMusic() end
    end
    -- 联机客户端只响应服务器，死亡和旁观不会中断广播的音乐。
    if Game.IsMultiplayer then return end
    local now = Timer.GetTime()
    if now < nextCheck then return end
    nextCheck = now + 0.25

    local player = Character.Controlled
    if not player or player.Removed or player.IsDead or not player.IsHuman then
        stopMusic()
        return
    end
    if listener ~= player then
        stopMusic()
        listener = player
    end
    if team ~= player.TeamID then
        roster, armed = {}, false
        team = player.TeamID
    end

    for character in Character.CharacterList do
        if not character.Removed and character.IsHuman and character.TeamID == team then
            roster[character] = character.IsDead
            if character ~= player and not character.IsDead then armed = true end
        end
    end

    local alone = armed
    for character, dead in pairs(roster) do
        -- shortcut: 未确认死亡的离场队友仍阻止触发，需要服务器权威名单时再扩展。
        if character ~= player and not dead then
            alone = false
            break
        end
    end
    if not alone then
        stopMusic()
    elseif not played then
        playMusic()
    elseif channel and not channel.IsPlaying then
        stopMusic()
    end
end)
