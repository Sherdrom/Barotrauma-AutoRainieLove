local script = "Lua/Autorun/AutoRainieLove.lua"
local function human(team)
    return { TeamID = team or 1, IsHuman = true, IsDead = false, Removed = false }
end

local function setup(options)
    options = options or {}
    local state = { hooks = {}, messages = {}, plays = 0, disposals = 0, time = 0, sent = {}, receivers = {}, channels = {} }
    local env = setmetatable({ SERVER = options.server or false }, { __index = _G })
    env.print = function(message) table.insert(state.messages, message) end
    env.Hook = { Add = function(event, name, callback)
        assert(name == "AutoRainieLove")
        state.hooks[event] = callback
    end, HookMethodType = { Before = "before" }, Patch = function(id, class, method, types, callback, when)
        assert(id == "AutoRainieLove" and class == "Barotrauma.SoundPlayer" and method == "UpdateMusic")
        assert(types[1] == "System.Single" and when == "before")
        state.musicPatch = callback
    end, RemovePatch = function() state.musicPatch = nil end }
    env.CharacterTeamType = { Team1 = 1, Team2 = 2 }
    env.DeliveryMethod = { Reliable = "reliable" }
    env.Networking = {
        Start = function(name)
            assert(name == "AutoRainieLove.Music")
            local message = {}
            message.WriteBoolean = function(value) message.value = value end
            return message
        end,
        Send = function(message, connection, delivery)
            assert(options.server and connection == nil and delivery == "reliable")
            table.insert(state.sent, message.value)
            for _, client in ipairs(state.clients or {}) do client.receive(message.value) end
        end,
        Receive = function(name, callback) state.receivers[name] = callback end,
    }
    env.Descriptors = { ["Barotrauma.SoundPlayer"] = "soundplayer" }
    env.LuaUserData = {
        CreateStatic = function(name)
            assert(not options.server and name == "Barotrauma.Sounds.SoundManager")
            return { SourceCount = 32 }
        end,
        CreateEnumTable = function(name)
            assert(name == "Barotrauma.Sounds.SoundManager+SourcePoolIndex")
            return { Default = 0, Voice = 1 }
        end,
        MakeFieldAccessible = function(descriptor, field)
            assert(descriptor == "soundplayer" and field == "musicChannel")
        end,
    }
    env.SoundPlayer = { musicChannel = {} }
    env.Timer = { GetTime = function() return state.time end }
    env.Identifier = function(value) return value end
    env.File = { Exists = function(path)
        assert(path == "mod/Sounds/last_survivor.ogg")
        return not options.missing
    end }
    env.Game = { RoundStarted = true, IsMultiplayer = options.multiplayer or options.server or false, SoundManager = {
        GetSoundChannelFromIndex = function(pool, index) return state.channels[pool .. ":" .. index] end,
        LoadSound = function(path, stream)
        assert(not options.server)
        assert(path == "mod/Sounds/last_survivor.ogg" and stream == true)
        if options.badAudio then error("bad Ogg") end
        if options.noDevice then return nil end
        state.sound = { Dispose = function() state.disposals = state.disposals + 1 end }
        state.sound.Play = function(gain, category)
            assert(gain == 1 and category == "music")
            if options.noChannel then return nil end
            state.plays = state.plays + 1
            state.channel = { Category = "music", IsPlaying = true, Dispose = function() state.stopped = true end }
            state.channels["0:31"] = state.channel
            return state.channel
        end
        return state.sound
    end } }
    env.Character = {}
    assert(loadfile(script, "t", env))("mod")
    function state.receive(value)
        state.receivers["AutoRainieLove.Music"]({ ReadBoolean = function() return value end })
    end
    function state.tick(player, characters)
        env.Character.Controlled = player
        local index = 0
        env.Character.CharacterList = function()
            index = index + 1
            return characters[index]
        end
        state.time = state.time + 0.3
        state.hooks.think()
    end
    state.env = env
    return state
end

local count = 0
local function test(name, callback)
    callback()
    count = count + 1
    print("PASS " .. name)
end

test("last survivor, unconscious ally, enemies, once per round", function()
    local s, me, a, b, enemy, pet = setup(), human(), human(), human(), human(2), human()
    pet.IsHuman = false
    local crew = { me, a, b, enemy, pet }
    s.tick(me, crew)
    a.IsDead, b.IsUnconscious = true, true
    s.tick(me, crew)
    assert(s.plays == 0)
    b.IsDead = true
    s.tick(me, crew)
    assert(s.plays == 1 and s.channel.Looping == true and s.channel.MuteBackgroundMusic)
    s.tick(me, crew)
    assert(s.plays == 1)
    a.IsDead = false
    s.tick(me, crew)
    assert(s.stopped and s.disposals == 1)
    a.IsDead = true
    s.tick(me, crew)
    assert(s.plays == 1)
    s.hooks.roundEnd()
    s.hooks.roundStart()
    a.IsDead = false
    s.tick(me, crew)
    a.IsDead = true
    s.tick(me, crew)
    assert(s.plays == 2)
end)

test("solo, spectator, late join among corpses, total wipe", function()
    local s, me, ally = setup(), human(), human()
    s.tick(me, { me })
    s.tick(nil, { me, ally })
    ally.IsDead = true
    s.tick(me, { me, ally })
    assert(s.plays == 0)
    ally.IsDead = false
    s.tick(me, { me, ally })
    me.IsDead, ally.IsDead = true, true
    s.tick(me, { me, ally })
    assert(s.plays == 0)
end)

test("unconfirmed removal is not death; confirmed corpse removal is", function()
    local s, me, a, b = setup(), human(), human(), human()
    s.tick(me, { me, a, b })
    b.IsDead = true
    s.tick(me, { me, b })
    assert(s.plays == 0)
    s.hooks["character.death"](a)
    s.tick(me, { me })
    assert(s.plays == 1)
end)

test("revival and reinforcement prevent or stop playback", function()
    local s, me, a, b = setup(), human(), human(), human()
    s.tick(me, { me, a })
    a.IsDead = true
    s.hooks["character.death"](a)
    a.IsDead = false
    s.tick(me, { me, a })
    assert(s.plays == 0)
    a.IsDead = true
    s.tick(me, { me, a })
    s.tick(me, { me, a, b })
    assert(s.plays == 1 and s.stopped)
end)

for _, event in ipairs({ "roundEnd", "roundStart", "stop", "death", "spectate", "switch", "channelStopped", "menu" }) do
    test("audio cleanup: " .. event, function()
        local s, me, ally = setup(), human(), human()
        s.tick(me, { me, ally })
        ally.IsDead = true
        s.tick(me, { me, ally })
        if s.hooks[event] then s.hooks[event]()
        elseif event == "death" then me.IsDead = true
        elseif event == "spectate" then me = nil
        elseif event == "switch" then me = human()
        elseif event == "channelStopped" then s.channel.IsPlaying = false
        elseif event == "menu" then s.env.Game.RoundStarted = false end
        s.tick(me, { ally })
        assert(s.stopped and s.disposals == 1 and s.plays == 1)
    end)
end

for _, option in ipairs({ "missing", "badAudio", "noDevice", "noChannel" }) do
    test("audio error does not spam: " .. option, function()
        local s, me, ally = setup({ [option] = true }), human(), human()
        s.tick(me, { me, ally })
        ally.IsDead = true
        s.tick(me, { me, ally })
        s.tick(me, { me, ally })
        assert(s.plays == 0 and #s.messages == 1)
        if option == "noChannel" then assert(s.disposals == 1) end
        if option == "missing" then
            s.hooks.roundStart()
            ally.IsDead = false
            s.tick(me, { me, ally })
            ally.IsDead = true
            s.tick(me, { me, ally })
            assert(#s.messages == 1)
        end
    end)
end

test("server broadcasts to survivor, dead player and spectator without client audio APIs", function()
    local server = setup({ server = true })
    local me, ally, bot, npc, pet = human(), human(), human(), human(3), human()
    pet.IsHuman = false
    local clients = { setup({ multiplayer = true }), setup({ multiplayer = true }), setup({ multiplayer = true }) }
    server.clients = clients
    assert(next(server.receivers) == nil and server.musicPatch == nil)
    server.tick(nil, { me, ally, bot, npc, pet })
    ally.IsDead = true
    server.tick(nil, { me, ally, bot, npc, pet })
    assert(#server.sent == 0)
    bot.IsDead = true
    server.tick(nil, { me, ally, bot, npc, pet })
    assert(#server.sent == 1 and server.sent[1] == true)
    clients[1].tick(me, { me })
    clients[2].tick(ally, { ally })
    clients[3].tick(nil, {})
    for _, client in ipairs(clients) do
        assert(client.plays == 1 and client.channel.Looping == true and not client.stopped)
        client.receive(true)
        assert(client.plays == 1)
    end
    me.IsDead = true
    server.tick(nil, { me, ally, bot })
    assert(#server.sent == 2 and server.sent[2] == false)
    for _, client in ipairs(clients) do assert(client.stopped) end
end)

test("multiplayer clients never decide locally, ignore out of round messages", function()
    local s, me, ally = setup({ multiplayer = true }), human(), human()
    s.tick(me, { me, ally })
    ally.IsDead = true
    s.tick(me, { me, ally })
    assert(s.plays == 0)
    s.env.Game.RoundStarted = false
    s.receive(true)
    assert(s.plays == 0)
end)

test("server requires a group, counts both player teams, ignores unconsciousness", function()
    local s, a, b = setup({ server = true }), human(), human(2)
    s.tick(nil, { a })
    assert(#s.sent == 0)
    s.tick(nil, { a, b })
    b.IsUnconscious = true
    s.tick(nil, { a, b })
    assert(#s.sent == 0)
    b.IsDead = true
    s.tick(nil, { a, b })
    assert(#s.sent == 1)
end)

test("server reinforcement stops music, no repeat until next round", function()
    local s, a, b = setup({ server = true }), human(), human()
    s.tick(nil, { a, b })
    b.IsDead = true
    s.tick(nil, { a, b })
    b.IsDead = false
    s.tick(nil, { a, b })
    b.IsDead = true
    s.tick(nil, { a, b })
    assert(#s.sent == 2 and s.sent[1] and not s.sent[2])
    s.hooks.roundStart()
    b.IsDead = false
    s.tick(nil, { a, b })
    b.IsDead = true
    s.tick(nil, { a, b })
    assert(#s.sent == 3 and s.sent[3])
    s.hooks.roundEnd()
    assert(#s.sent == 4 and not s.sent[4])
end)

test("server full wipe never starts music", function()
    local s, a, b = setup({ server = true }), human(), human()
    s.tick(nil, { a, b })
    a.IsDead, b.IsDead = true, true
    s.tick(nil, { a, b })
    assert(#s.sent == 0)
end)

test("stop other music immediately, suppress restart, preserve effects and resume afterwards", function()
    local s = setup({ multiplayer = true })
    local function track(category)
        local value = { Category = category }
        value.Dispose = function() value.stopped = true end
        return value
    end
    local background, noise, otherMod, effect, voice = track("music"), track("default"), track("music"), track("default"), track("voip")
    s.env.SoundPlayer.musicChannel = { [0] = background, [2] = noise }
    s.channels = { ["0:0"] = background, ["0:1"] = otherMod, ["0:2"] = effect, ["1:0"] = voice }
    s.receive(true)
    assert(background.stopped and noise.stopped and otherMod.stopped)
    assert(not effect.stopped and not voice.stopped and not s.stopped)
    local parameters = {}
    s.musicPatch(nil, parameters)
    assert(parameters.PreventExecution)
    local restarted = track("music")
    s.channels["0:3"] = restarted
    s.tick(nil, {})
    assert(restarted.stopped and not s.stopped)
    s.receive(false)
    parameters = {}
    s.musicPatch(nil, parameters)
    assert(not parameters.PreventExecution)
    s.hooks.stop()
    assert(s.musicPatch == nil)
end)

test("missing music leaves other audio and normal music updates alone", function()
    local s = setup({ multiplayer = true, missing = true })
    local other = { Dispose = function() error("must not stop other music") end }
    s.env.SoundPlayer.musicChannel = { other }
    s.receive(true)
    local parameters = {}
    s.musicPatch(nil, parameters)
    assert(not parameters.PreventExecution and #s.messages == 1)
end)

print(string.format("%d tests passed", count))
