assert(Automaton, "Automaton not found!")

------------------------------
--      Are you local?      --
------------------------------

local L = AceLibrary("AceLocale-2.2"):new("Automaton_Gossip")
local GossipData = {}
local QuestData = {}
local PreferredGossipTypes = {"trainer", "vendor"}
local UnsafeGossipTypes = {
	["binder"] = true,
	["unlearn"] = true,
}

local function GetGossipQuestList(counter, getter, stride)
	local quests = {}
	if getter then
		quests = { getter() }
	end

	local count
	if counter then
		count = counter() or 0
	end

	local inferred = 0
	while quests[inferred*stride + 1] do
		inferred = inferred + 1
	end

	if not count or count < inferred then
		count = inferred
	end

	return count or 0, quests
end

----------------------------------
--      Module Declaration      --
----------------------------------

Automaton_Gossip = Automaton:NewModule("Gossip")
Automaton_Gossip.modulename = L["Gossip & Quest"]
Automaton_Gossip.moduledesc = L["Automatically complete quests and skip gossip text"]
Automaton_Gossip.options = {
	questHaste = {
		order = 2,
		type = "toggle",
		name = L["Quest"],
		desc = "Automatically accept and complete all quests. Hold Shift to pause automation.",
		get = function() return Automaton_Gossip.db.profile.questHaste end,
		set = function(v) Automaton_Gossip.db.profile.questHaste = v end,
	},
}

------------------------------
--      Initialization      --
------------------------------

function Automaton_Gossip:OnInitialize()
	self.db = Automaton:AcquireDBNamespace("Gossip")
	Automaton:RegisterDefaults("Gossip", "profile", {
		questHaste = false,
	})

	GossipData = Automaton_Gossip:GetGossipData()
	QuestData = Automaton_Gossip:GetQuestData()

	self:RegisterOptions(self.options)
	self.options.enabled.name = L["Gossip"]
	self.options.debugging.name = L["Debug"]
end

function Automaton_Gossip:OnEnable()
	self:RegisterEvent("GOSSIP_SHOW")
	self:RegisterEvent("QUEST_PROGRESS")
	self:RegisterEvent("QUEST_COMPLETE")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_GREETING")
end

function Automaton_Gossip:OnDisable()
	self:UnregisterAllEvents()
end

------------------------------
--      Event Handlers      --
------------------------------

function Automaton_Gossip:GOSSIP_SHOW()
	if IsShiftKeyDown() then return end

	local gossipCount, gossipOptions = self:GetGossipOptionList()
	self:Debug("GOSSIP_SHOW: "..gossipCount.." gossip options.")

	if self.db.profile.questHaste and self:QuestHasteGossip() then
		self:Debug("Quest automation handled gossip event.")
		return
	end

	if self.db.profile.questHaste then
		self:SelectGossipOptionAfterQuests(gossipCount, gossipOptions)
		return
	end

	if gossipCount == 1 and self:SelectSingleGossipOption(gossipOptions[1], gossipOptions[2]) then
		return
	end

	local g = self:ProcessGossip(gossipCount, gossipOptions)

	if self:SelectGossip(g, true) then
		return
	end

	if self:SelectGossip(g) then
		return
	end

	if self:CheckQuests(self:ProcessQuestOptions(self:GetGossipActiveQuestOptions(), true), SelectGossipActiveQuest) then
		return
	end

	if self:CheckQuests(self:ProcessQuestOptions(self:GetGossipAvailableQuestOptions()), SelectGossipAvailableQuest) then
		return
	end
end

function Automaton_Gossip:GetGossipOptionList()
	local options = { GetGossipOptions() }
	local count = 0
	while options[count*2 + 1] do
		count = count + 1
	end

	if GetNumGossipOptions then
		count = GetNumGossipOptions() or count
	end

	return count, options
end

function Automaton_Gossip:GetGossipAvailableQuestList()
	return GetGossipQuestList(GetNumGossipAvailableQuests, GetGossipAvailableQuests, 3)
end

function Automaton_Gossip:GetGossipActiveQuestList()
	return GetGossipQuestList(GetNumGossipActiveQuests, GetGossipActiveQuests, 4)
end

function Automaton_Gossip:GetMaxTableIndex(values)
	local max = 0
	for k in pairs(values) do
		if type(k) == "number" and k > max then
			max = k
		end
	end
	return max
end

function Automaton_Gossip:GetGossipQuestOptions(getter)
	local values = {}
	if getter then
		values = { getter() }
	end

	local quests = {}
	local optionIndex = 0
	local max = self:GetMaxTableIndex(values)
	for k = 1, max do
		if type(values[k]) == "string" then
			optionIndex = optionIndex + 1
			tinsert(quests, {values[k], optionIndex, nil, values[k+1]})
		end
	end
	return quests
end

function Automaton_Gossip:GetGossipAvailableQuestOptions()
	return self:GetGossipQuestOptions(GetGossipAvailableQuests)
end

function Automaton_Gossip:GetGossipActiveQuestOptions()
	return self:GetGossipQuestOptions(GetGossipActiveQuests)
end

function Automaton_Gossip:HasGossipQuests()
	return table.getn(self:GetGossipAvailableQuestOptions()) > 0 or table.getn(self:GetGossipActiveQuestOptions()) > 0
end

function Automaton_Gossip:SelectSingleGossipOption(title, gossipType)
	if gossipType then
		gossipType = string.lower(gossipType)
	end

	if self:HasGossipQuests() and not (gossipType == "gossip") then
		return false
	end

	self:Debug("Selecting only gossip option: "..tostring(title).." ("..tostring(gossipType)..")")
	SelectGossipOption(1)
	return true
end

function Automaton_Gossip:NormalizeGossipType(gossipType)
	if gossipType then
		return string.lower(gossipType)
	end
end

function Automaton_Gossip:IsUnsafeGossipType(gossipType)
	return UnsafeGossipTypes[self:NormalizeGossipType(gossipType)]
end

function Automaton_Gossip:SelectGossipOptionByIndex(index, title, gossipType)
	self:Debug("AutoGossip: "..tostring(title).." ("..tostring(gossipType)..")")
	SelectGossipOption(index)
	return true
end

function Automaton_Gossip:SelectGossipOptionByType(count, options, wantedType)
	options = options or {}
	count = count or table.getn(options) / 2
	for k = 1, count do
		local i = (k-1)*2 + 1
		local title, gossipType = options[i], self:NormalizeGossipType(options[i+1])
		if title and gossipType == wantedType then
			return self:SelectGossipOptionByIndex(k, title, gossipType)
		end
	end
	return false
end

function Automaton_Gossip:HasUnsafeGossipOption(count, options)
	options = options or {}
	count = count or table.getn(options) / 2
	for k = 1, count do
		local i = (k-1)*2 + 1
		if options[i] and self:IsUnsafeGossipType(options[i+1]) then
			return true
		end
	end
	return false
end

function Automaton_Gossip:SelectGossipOptionAfterQuests(count, options)
	options = options or {}
	count = count or table.getn(options) / 2

	if self:HasUnsafeGossipOption(count, options) then
		for k = 1, table.getn(PreferredGossipTypes) do
			if self:SelectGossipOptionByType(count, options, PreferredGossipTypes[k]) then
				return true
			end
		end
	end

	for k = 1, count do
		local i = (k-1)*2 + 1
		local title, gossipType = options[i], self:NormalizeGossipType(options[i+1])
		if title and not self:IsUnsafeGossipType(gossipType) then
			return self:SelectGossipOptionByIndex(k, title, gossipType)
		end
	end

	return false
end

function Automaton_Gossip:SelectGossip(gossips, gossipOnly)
	if table.getn(gossips) > 1 then
		if not gossipOnly then
			self:Debug("Too many gossips to pick from, doing nothing.")
		end
		return false
	elseif table.getn(gossips) == 1 then
		if gossipOnly and not (gossips[1][2] == "gossip") then
			return false
		end

		local z = self:GetGossipAvailableQuestOptions()
		local x = self:GetGossipActiveQuestOptions()
		if (table.getn(x) > 0 or table.getn(z) > 0) and not (gossips[1][2] == "gossip") then
			self:Debug("Not AutoGossiping because there's an available or active quest.")
		else
			self:Debug(gossips[1][1])
			SelectGossipOption(gossips[1][3])
			return true
		end
	end

	return false
end

function Automaton_Gossip:QUEST_GREETING()
	if not self.db.profile.questHaste or IsShiftKeyDown() then return end

	local available = {}
	local active = {}

	for k = 1, GetNumAvailableQuests() do
		tinsert(available, {GetAvailableTitle(k), k})
	end
	for k = 1, GetNumActiveQuests() do
		local title, isComplete = GetActiveTitle(k)
		tinsert(active, {title, k, isComplete})
	end

	self:QuestHasteSelectQuest(active, available, SelectActiveQuest, SelectAvailableQuest)
end

function Automaton_Gossip:QUEST_DETAIL()
	if self.db.profile.questHaste then
		if IsShiftKeyDown() then return end
		AcceptQuest()
		return
	end

	local q = GetTitleText()
	if QuestData[q] then
		self:Debug("AutoAccepting "..q..".")
		AcceptQuest()
	end
end

function Automaton_Gossip:QUEST_PROGRESS()
	if self.db.profile.questHaste then
		if IsShiftKeyDown() then return end
		if IsQuestCompletable() then
			CompleteQuest()
		end
		return
	end

	local q = GetTitleText()
	if QuestData[q] and IsQuestCompletable() then
		self:Debug("AutoCompleting "..q..".")
		CompleteQuest()
	end
end

function Automaton_Gossip:QUEST_COMPLETE()
	if self.db.profile.questHaste then
		if IsShiftKeyDown() then return end
		self:QuestHasteCompleteReward()
		return
	end

	local q = GetTitleText()
	if QuestData[q] then
		self:Debug("AutoRewardPicking "..q..".")
		GetQuestReward(0)
	end
end

function Automaton_Gossip:QuestHasteGossip()
	if self:QuestHasteSelectQuest(self:GetGossipActiveQuestOptions(), self:GetGossipAvailableQuestOptions(), SelectGossipActiveQuest, SelectGossipAvailableQuest) then
		return true
	end
	return false
end

function Automaton_Gossip:ProcessAnyQuestList(count, stride, completeOffset, values)
	local quests = {}
	values = values or {}
	count = count or 0
	for k = 1, count do
		local i = (k-1)*stride + 1
		local title = values[i]
		if title then
			tinsert(quests, {title, k, completeOffset and values[i+completeOffset]})
		end
	end
	return quests
end

function Automaton_Gossip:ProcessAnyQuests(count, stride, completeOffset, ...)
	return self:ProcessAnyQuestList(count, stride, completeOffset, arg)
end

function Automaton_Gossip:GetQuestLogEntryInfo(index)
	local title, level, tag, fourth, fifth, sixth, seventh = GetQuestLogTitle(index)
	if seventh ~= nil or type(fourth) == "number" or (fourth == nil and fifth == true) then
		return title, fifth, sixth, seventh
	end
	return title, fourth, fifth, sixth
end

function Automaton_Gossip:IsCompleteValue(value)
	return value == true or value == 1 or value == "1" or value == "true" or value == "complete" or value == "COMPLETE" or value == "completed" or value == "COMPLETED"
end

function Automaton_Gossip:HasRequiredItems(items)
	if not items then
		return true
	end

	for item, quantity in pairs(items) do
		if (tonumber(self:SearchBagsForQuantity(item)) or 0) < quantity then
			return false
		end
	end

	return true
end

function Automaton_Gossip:HasRequiredQuestItems(title)
	local data = QuestData[title]
	if not data then
		return true
	end

	local faction = UnitFactionGroup("player")
	if faction and not self:HasRequiredItems(data[faction]) then
		return false
	end

	return self:HasRequiredItems(data.items)
end

function Automaton_Gossip:IsQuestLogEntryComplete(index, title, isHeader, isComplete)
	if not title or isHeader then
		return false
	end

	local objectives = GetNumQuestLeaderBoards(index) or 0
	if not self:IsCompleteValue(isComplete) and objectives == 0 then
		return false
	end

	for k = 1, objectives do
		local text, objectiveType, finished = GetQuestLogLeaderBoard(k, index)
		if text and not self:IsCompleteValue(finished) then
			return false
		end
	end

	return self:HasRequiredQuestItems(title)
end

function Automaton_Gossip:GetQuestLogCompletionMap()
	local known = {}
	local completed = {}
	local collapsed = {}

	for k = GetNumQuestLogEntries(), 1, -1 do
		local title, isHeader, isCollapsed = self:GetQuestLogEntryInfo(k)
		if title and isHeader and isCollapsed then
			collapsed[title] = true
			ExpandQuestHeader(k)
		end
	end

	for k = 1, GetNumQuestLogEntries() do
		local title, isHeader, isCollapsed, isComplete = self:GetQuestLogEntryInfo(k)
		if title and not isHeader then
			known[title] = true
			if self:IsQuestLogEntryComplete(k, title, isHeader, isComplete) then
				completed[title] = true
			end
		end
	end

	for k = GetNumQuestLogEntries(), 1, -1 do
		local title, isHeader = self:GetQuestLogEntryInfo(k)
		if title and isHeader and collapsed[title] then
			CollapseQuestHeader(k)
		end
	end

	return completed, known
end

function Automaton_Gossip:GetCompletedQuestLogTitles()
	local completed = self:GetQuestLogCompletionMap()
	return completed
end

function Automaton_Gossip:IsActiveQuestCompletable(quest, completed, known, completeValue)
	local title = quest and quest[1]
	if not title or not self:HasRequiredQuestItems(title) then
		return false
	end

	if completeValue == nil then
		completeValue = quest[3]
	end

	if self:IsCompleteValue(completeValue) then
		return true
	end

	if completed and completed[title] then
		return true
	end

	if completeValue ~= nil or (known and known[title]) then
		return false
	end

	return false
end

function Automaton_Gossip:IsQuestLogFull()
	local entries, quests = GetNumQuestLogEntries()
	local maxQuests = MAX_QUESTS or 20
	entries = entries or 0

	if not quests then
		quests = 0
		for k = 1, entries do
			local title, isHeader = self:GetQuestLogEntryInfo(k)
			if title and not isHeader then
				quests = quests + 1
			end
		end
	end

	return quests >= maxQuests
end

function Automaton_Gossip:NotifyQuestLogFull()
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("Quest Log full", 1, 0, 0)
	end
	PlaySound("igQuestFailed")
end

function Automaton_Gossip:QuestHasteSelectQuest(active, available, complete, accept)
	local completed, known = self:GetQuestLogCompletionMap()

	for k = 1, table.getn(active) do
		local quest = active[k]
		if self:IsActiveQuestCompletable(quest, completed, known) then
			complete(quest[2])
			return true
		end
	end

	if table.getn(available) > 0 then
		if self:IsQuestLogFull() then
			self:NotifyQuestLogFull()
			return true
		end
		accept(available[1][2])
		return true
	end

	return false
end

function Automaton_Gossip:QuestHasteCompleteReward()
	local choices = GetNumQuestChoices()
	if choices == 0 then
		GetQuestReward()
	elseif choices == 1 then
		GetQuestReward(1)
	end
end

function Automaton_Gossip:MatchesGossipData(data, title)
	if table.getn(data) == 0 then
		return true
	end

	for k,v in pairs(data) do
		if v == title then
			return true
		end
	end

	return false
end

function Automaton_Gossip:ProcessGossip(count, options)
	local priorityGossips = {}
	local gossips = {}
	local services = {}
	options = options or {}
	count = count or table.getn(options) / 2
	for k = 1, count do
		local i = (k-1)*2 + 1
		local title, gossipType = options[i], options[i+1]
		if gossipType then
			gossipType = string.lower(gossipType)
		end
		self:Debug("Gossip option "..k..": "..tostring(title).." ("..tostring(gossipType)..")")
		if gossipType == "gossip" then
			if GossipData[gossipType] and self:MatchesGossipData(GossipData[gossipType], title) then
				tinsert(priorityGossips, {title, gossipType, k})
			else
				tinsert(gossips, {title, gossipType, k})
			end
		elseif GossipData[gossipType] and self:MatchesGossipData(GossipData[gossipType], title) then
			tinsert(services, {title, gossipType, k})
		end
	end

	if table.getn(priorityGossips) > 0 then
		return priorityGossips
	end

	if table.getn(gossips) > 0 then
		return gossips
	end

	return services
end

function Automaton_Gossip:ProcessQuestOptions(options, requireComplete)
	local quests = {}
	local completed, known
	options = options or {}
	for k = 1, table.getn(options) do
		local quest = options[k]
		local title = quest[1]
		if QuestData[title] and self:HasRequiredQuestItems(title) then
			if not requireComplete then
				tinsert(quests, {title, quest[4], quest[2]})
			else
				if not completed then
					completed, known = self:GetQuestLogCompletionMap()
				end
				if self:IsActiveQuestCompletable(quest, completed, known, quest[3]) then
					tinsert(quests, {title, quest[4], quest[2]})
				end
			end
		end
	end
	return quests
end

function Automaton_Gossip:ProcessQuestList(count, stride, values, completeOffset)
	local quests = {}
	local completed, known
	values = values or {}
	count = count or 0
	for k = 1, count do
		local i = (k-1)*stride + 1
		local title, level = values[i], values[i+1]
		if QuestData[title] then
			if self:HasRequiredQuestItems(title) then
				local quest = {title, level, k}
				if not completeOffset then
					tinsert(quests, quest)
				else
					if not completed then
						completed, known = self:GetQuestLogCompletionMap()
					end
					if self:IsActiveQuestCompletable(quest, completed, known, values[i+completeOffset]) then
						tinsert(quests, quest)
					end
				end
			end
		end
	end
	return quests
end

function Automaton_Gossip:ProcessQuests(count, stride, ...)
	return self:ProcessQuestList(count, stride, arg)
end

function Automaton_Gossip:CheckQuests(quests, func)
	if table.getn(quests) > 1 then
		local quest, priority = nil, 0
		for k,v in pairs(quests) do
			self:Debug(k,v)
			if QuestData[v[1]].priority and QuestData[v[1]].priority > priority then
				priority = QuestData[v[1]].priority
				quest = k
			end
			if not quest then 
				quest = 1
			end
		end
		self:Debug("AutoActiveQuest: "..quests[quest][1])
		func(quests[quest][3])
		return true
	elseif table.getn(quests) == 1 then
		self:Debug("AutoActiveQuest: "..quests[1][1])
		func(quests[1][3])
		return true
	end
	return false
end

function Automaton_Gossip:SearchBagsForQuantity(itemname)
	local quantity = 0
	for bag = 0, 4 do
		if GetContainerNumSlots(bag) > 0 then
			for slot = 0, GetContainerNumSlots(bag) do
				if GetContainerItemLink(bag, slot) then
					local _,_,link = string.find(GetContainerItemLink(bag, slot), "(item:%d+:%d+:%d+:%d+)")
					local item = GetItemInfo(link)
					if item == itemname then
						local _,q = GetContainerItemInfo(bag, slot)
						quantity = quantity + q
					end
				end
			end
		end
	end
	return quantity
end
