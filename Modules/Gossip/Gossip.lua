assert(Automaton, "Automaton not found!")

------------------------------
--      Are you local?      --
------------------------------

local L = AceLibrary("AceLocale-2.2"):new("Automaton_Gossip")
local GossipData = {}
local QuestData = {}

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

	if self.db.profile.questHaste and self:QuestHasteGossip() then
		return
	end
	
	local g = self:ProcessGossip(GetGossipOptions())

	if table.getn(g) > 1 then
		self:Debug("Too many gossips to pick from, doing nothing.")
		return
	elseif table.getn(g) == 1 then
		local z,_ = GetGossipAvailableQuests()
		local x,_ = GetGossipActiveQuests()
		if (x or z) and not (g[1][2] == "gossip") then
			self:Debug("Not AutoGossiping because there's an available or active quest.")
		else
			self:Debug(g[1][1])
			SelectGossipOption(g[1][3])
			return
		end
	end

	if self:CheckQuests(self:ProcessQuests(GetNumGossipActiveQuests(), 4, GetGossipActiveQuests()), SelectGossipActiveQuest) then
		return
	end
	if self:CheckQuests(self:ProcessQuests(GetNumGossipAvailableQuests(), 3, GetGossipAvailableQuests()), SelectGossipAvailableQuest) then
		return
	end
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

	self:QuestHasteSelectQuest(available, active, SelectAvailableQuest, SelectActiveQuest)
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
	if self:QuestHasteSelectQuest(self:ProcessAnyQuests(GetNumGossipAvailableQuests(), 3, nil, GetGossipAvailableQuests()), self:ProcessAnyQuests(GetNumGossipActiveQuests(), 4, 3, GetGossipActiveQuests()), SelectGossipAvailableQuest, SelectGossipActiveQuest) then
		return true
	end
	return false
end

function Automaton_Gossip:ProcessAnyQuests(count, stride, completeOffset, ...)
	local quests = {}
	count = count or 0
	for k = 1, count do
		local i = (k-1)*stride + 1
		local title = arg[i]
		if title then
			tinsert(quests, {title, k, completeOffset and arg[i+completeOffset]})
		end
	end
	return quests
end

function Automaton_Gossip:GetQuestLogEntryInfo(index)
	local title, level, tag, group, header, complete, complete2 = GetQuestLogTitle(index)
	local version, build, date, toc = GetBuildInfo()
	toc = tonumber(toc)
	if toc and toc >= 20000 and toc < 60000 then
		return title, header, complete, complete2
	end
	return title, group, header, complete
end

function Automaton_Gossip:GetCompletedQuestLogTitles()
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
		if title and not isHeader and isComplete then
			completed[title] = true
		end
	end

	for k = GetNumQuestLogEntries(), 1, -1 do
		local title, isHeader = self:GetQuestLogEntryInfo(k)
		if title and isHeader and collapsed[title] then
			CollapseQuestHeader(k)
		end
	end

	return completed
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

function Automaton_Gossip:QuestHasteSelectQuest(available, active, accept, complete)
	for k = 1, table.getn(active) do
		local quest = active[k]
		if quest[3] then
			complete(quest[2])
			return true
		end
	end

	local completed = self:GetCompletedQuestLogTitles()
	for k = 1, table.getn(active) do
		local quest = active[k]
		if completed[quest[1]] then
			complete(quest[2])
			return true
		end
	end

	if table.getn(active) > 0 and self:IsQuestLogFull() then
		complete(active[1][2])
		return true
	end

	if table.getn(available) > 0 then
		accept(available[1][2])
		return true
	end

	if table.getn(active) > 0 then
		complete(active[1][2])
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

function Automaton_Gossip:ProcessGossip(...)
	local gossips = {}
	for i = 1, table.getn(arg), 2 do
		local title, type = arg[i], arg[i+1]
		if GossipData[type] then
			if table.getn(GossipData[type]) == 0 then
				tinsert(gossips, {title, type, (i+1)/2})
			else
				for k,v in GossipData[type] do
					if v == title then
						tinsert(gossips, {title, type, (i+1)/2})
					end
				end
			end
		end
	end
	return gossips
end

function Automaton_Gossip:ProcessQuests(count, stride, ...)
	local quests = {}
	count = count or 0
	for k = 1, count do
		local i = (k-1)*stride + 1
		local title, level = arg[i], arg[i+1]
		if QuestData[title] then
			local good = true
			if QuestData[title][faction] then
				for k, v in pairs(QuestData[title][faction]) do
					if tonumber(self:SearchBagsForQuantity(k)) < v then
						good = false
						break
					end
				end
			end
			if QuestData[title].items then
				for k, v in QuestData[title].items do
					if tonumber(self:SearchBagsForQuantity(k)) < v then
						good = false
						break
					end
				end
			end
			if good then
				tinsert(quests, {title, level, k})
			end
		end
	end
	return quests
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
