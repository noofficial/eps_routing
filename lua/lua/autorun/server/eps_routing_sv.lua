if CLIENT then return end

util.AddNetworkString(EPS.NET.Open)
util.AddNetworkString(EPS.NET.Update)
util.AddNetworkString(EPS.NET.FullState)

local function isPlayerAllowed(ply)
	if not IsValid(ply) then return true end

	local allowed = EPS.Config.AllowedGroups or {}
	if #allowed == 0 then return true end

	local plyTeamName
	if team and ply.Team then
		plyTeamName = team.GetName(ply:Team())
	end

	for _, group in ipairs(allowed) do
		if group == "*" then return true end
		if ply:IsUserGroup(group) then return true end
		if plyTeamName and plyTeamName:lower() == group:lower() then return true end
	end

	return false
end

local function clampToUInt(value, bits)
	local maxValue = (2 ^ bits) - 1
	value = math.floor((value or 0) + 0.5)
	if value < 0 then value = 0 end
	if value > maxValue then value = maxValue end
	return value
end

local function sendFullState(target, shouldOpen)
	if not EPS.State then return end

	net.Start(EPS.NET.FullState)
	net.WriteBool(shouldOpen or false)
	net.WriteUInt(clampToUInt(EPS.GetBudget(), 16), 16)

	local subs = {}
	for _, sub in EPS.IterSubsystems() do
		subs[#subs + 1] = sub
	end

	net.WriteUInt(clampToUInt(#subs, 8), 8)

	for _, sub in ipairs(subs) do
		net.WriteString(sub.id)
		net.WriteString(sub.label or "")
		net.WriteUInt(clampToUInt(sub.min or 0, 16), 16)
		net.WriteUInt(clampToUInt(sub.max or EPS.GetBudget(), 16), 16)
		net.WriteUInt(clampToUInt(EPS.State.allocations[sub.id] or 0, 16), 16)
		net.WriteUInt(clampToUInt(EPS.State.demand[sub.id] or 0, 16), 16)
	end

	if istable(target) then
		net.Send(target)
	elseif IsValid(target) then
		net.Send(target)
	else
		net.Send(player.GetHumans())
	end
end

function EPS.BroadcastState(target, shouldOpen)
	sendFullState(target, shouldOpen)
end

local function applyAllocations(ply, incoming)
	if not EPS.State then
		EPS.ResetState()
	end

	EPS.State.allocations = EPS.State.allocations or {}
	EPS.State.demand = EPS.State.demand or {}

	local newAlloc = {}
	local sum = 0

	for _, sub in EPS.IterSubsystems() do
		local id = sub.id
		local raw = incoming[id]
		local clamped = raw and EPS.ClampAllocationForSubsystem(id, raw) or EPS.State.allocations[id]
		clamped = clamped or 0
		newAlloc[id] = clamped
		sum = sum + clamped
	end

	if sum > EPS.GetBudget() then
		return false, "Budget exceeded"
	end

	if currentSpike and currentSpike.target then
		local targetId = currentSpike.target
		local newValue = newAlloc[targetId]
		if newValue ~= nil then
			if not currentSpike.responded and newValue ~= currentSpike.startAlloc then
				currentSpike.responded = true
			end
			currentSpike.lastAlloc = newValue
		end
	end

	for id, value in pairs(newAlloc) do
		EPS.State.allocations[id] = value
		EPS.State.demand[id] = math.max(EPS.State.demand[id] or value, value)
	end

	EPS._RunChangeHookIfNeeded()

	return true
end

net.Receive(EPS.NET.Open, function(_, ply)
	if not isPlayerAllowed(ply) then return end
	sendFullState(ply, true)
end)

net.Receive(EPS.NET.Update, function(_, ply)
	if not isPlayerAllowed(ply) then return end

	local count = net.ReadUInt(8)
	local received = {}

	for _ = 1, count do
		local id = net.ReadString()
		local value = net.ReadUInt(16)
		received[id] = value
	end

	local ok, reason = applyAllocations(ply, received)

	if not ok then
		sendFullState(ply, false)
		if reason and IsValid(ply) and ply.ChatPrint then
			ply:ChatPrint("[EPS] " .. reason)
		end
		return
	end

	sendFullState(nil, false)
end)

local function pickWeighted(weights)
	local total = 0
	for _, weight in pairs(weights or {}) do
		if weight and weight > 0 then
			total = total + weight
		end
	end
	if total <= 0 then return nil end

	local roll = math.Rand(0, total)
	for id, weight in pairs(weights) do
		if weight and weight > 0 then
			if roll <= weight then return id end
			roll = roll - weight
		end
	end
end

local spikeTimerId = "EPS_SpikeTimer"
local currentSpike

local function pickAlertDeck()
	local cfg = EPS.Config.Spikes or {}
	local decks = cfg.AlertDecks
	if not istable(decks) or #decks == 0 then
		decks = { 1, 2, 3, 4, 5, 6, 11 }
	end
	return decks[math.random(#decks)]
end

local function broadcastSpikeAlert(deck)
	local cfg = EPS.Config.Spikes or {}
	local cmd = cfg.AlertCommand
	if not cmd or cmd == "" then return end

	local template = cfg.AlertMessage or "EPS relays need adjusting on Deck %s!"
	local message = string.format(template, tostring(deck or "?"))

	local full = string.Trim(cmd .. " " .. message)
	if full == "" then return end

	if RunConsoleCommand then
		RunConsoleCommand("say", full)
	else
		game.ConsoleCommand("say " .. full .. "\n")
	end
end

local function broadcastRecoveryAlert(deck)
	local cfg = EPS.Config.Spikes or {}
	local cmd = cfg.AlertCommand
	if not cmd or cmd == "" then return end

	local template = cfg.AlertRecoveryMessage or "EPS power allocation has been stabilized on Deck %s."
	local message = string.format(template, tostring(deck or "?"))

	local full = string.Trim(cmd .. " " .. message)
	if full == "" then return end

	if RunConsoleCommand then
		RunConsoleCommand("say", full)
	else
		game.ConsoleCommand("say " .. full .. "\n")
	end
end

local function scheduleNextSpike()
	local cfg = EPS.Config.Spikes
	if not cfg or not cfg.Enabled then return end

	local intervalMin = cfg.IntervalMin or 30
	local intervalMax = cfg.IntervalMax or 60
	if intervalMax < intervalMin then intervalMin, intervalMax = intervalMax, intervalMin end

	local interval = math.Rand(intervalMin, intervalMax)

	timer.Create(spikeTimerId, interval, 1, function()
		local target = pickWeighted(cfg.Weights or {})
		if not target or not EPS.State or not EPS.State.demand then
			scheduleNextSpike()
			return
		end

		local extraMin = cfg.ExtraDemandMin or 5
		local extraMax = cfg.ExtraDemandMax or 10
		if extraMax < extraMin then extraMin, extraMax = extraMax, extraMin end

		local extra = math.random(extraMin, extraMax)
		EPS.State.demand[target] = (EPS.State.demand[target] or EPS.State.allocations[target] or 0) + extra
		sendFullState(nil, false)

		local durMin = cfg.DurationMin or 10
		local durMax = cfg.DurationMax or 20
		if durMax < durMin then durMin, durMax = durMax, durMin end

		local duration = math.Rand(durMin, durMax)
		local deck = pickAlertDeck()

		currentSpike = {
			target = target,
			deck = deck,
			startAlloc = (EPS.State.allocations and EPS.State.allocations[target]) or 0,
			responded = false,
			expires = CurTime() + duration,
		}

		broadcastSpikeAlert(deck)

		timer.Simple(duration, function()
			local baseline = 0
			for _, sub in EPS.IterSubsystems() do
				if sub.id == target then
					baseline = sub.default or sub.min or 0
					break
				end
			end
			local current = EPS.State.allocations[target] or baseline
			EPS.State.demand[target] = math.max(baseline, current)
			sendFullState(nil, false)

			if currentSpike and currentSpike.target == target then
				if not currentSpike.responded then
					broadcastRecoveryAlert(currentSpike.deck)
				end
				currentSpike = nil
			end
			scheduleNextSpike()
		end)
	end)
end

hook.Add("Initialize", "EPS_StartSpikesOnInit", function()
	scheduleNextSpike()
end)

hook.Add("PlayerInitialSpawn", "EPS_SendInitialState", function(ply)
	timer.Simple(3, function()
		if IsValid(ply) then
			sendFullState(ply, false)
		end
	end)
end)

local function handleChatCommand(ply, text)
	local cmd = EPS.Config.Commands and EPS.Config.Commands.Chat
	if not cmd or cmd == "" then return end

	local trimmed = string.Trim(text or "")
	if trimmed:lower() == cmd:lower() and isPlayerAllowed(ply) then
		sendFullState(ply, true)
		return ""
	end
end

hook.Add("PlayerSay", "EPS_ChatCommand", handleChatCommand)

local conCommand = EPS.Config.Commands and EPS.Config.Commands.ConCommand or "eps_open"

concommand.Add(conCommand, function(ply)
	if not IsValid(ply) then return end
	if not isPlayerAllowed(ply) then return end
	sendFullState(ply, true)
end, nil, "Open the EPS routing interface")

concommand.Add("eps_sync", function(ply)
	if IsValid(ply) then
		sendFullState(ply, false)
	else
		sendFullState(nil, false)
	end
end, nil, "Sync EPS state to yourself (or everyone from server console)")

hook.Add("ShutDown", "EPS_StopSpikeTimer", function()
	if timer.Exists(spikeTimerId) then
		timer.Remove(spikeTimerId)
	end
end)