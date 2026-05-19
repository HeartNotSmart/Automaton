assert(Automaton, "Automaton not found!")

------------------------------
--      Are you local?      --
------------------------------

local L = AceLibrary("AceLocale-2.2"):new("Automaton_Quest")

----------------------------
--      Localization      --
----------------------------

L:RegisterTranslations("enUS", function() return {
	["Quest"] = true,
	["QuestHaste mode"] = true,
	["Automatically accept and complete all quests."] = true,
	["Automatically accept and complete all quests. Hold Shift to pause automation."] = true,
} end)

L:RegisterTranslations("ruRU", function() return {
	["Quest"] = "Quest",
	["QuestHaste mode"] = "QuestHaste mode",
	["Automatically accept and complete all quests."] = "Automatically accept and complete all quests.",
	["Automatically accept and complete all quests. Hold Shift to pause automation."] = "Automatically accept and complete all quests. Hold Shift to pause automation.",
} end)

L:RegisterTranslations("koKR", function() return {
	["Quest"] = "Quest",
	["QuestHaste mode"] = "QuestHaste mode",
	["Automatically accept and complete all quests."] = "Automatically accept and complete all quests.",
	["Automatically accept and complete all quests. Hold Shift to pause automation."] = "Automatically accept and complete all quests. Hold Shift to pause automation.",
} end)

----------------------------------
--      Module Declaration      --
----------------------------------

Automaton_Quest = Automaton:NewModule("Quest")
Automaton_Quest.modulename = L["Quest"]
Automaton_Quest.moduledesc = L["Automatically accept and complete all quests."]
Automaton_Quest.enabledname = L["QuestHaste mode"]
Automaton_Quest.enableddesc = L["Automatically accept and complete all quests. Hold Shift to pause automation."]
Automaton_Quest.options = {}

------------------------------
--      Initialization      --
------------------------------

function Automaton_Quest:OnInitialize()
	self.db = Automaton:AcquireDBNamespace("Quest")
	local gossipDB = Automaton:AcquireDBNamespace("Gossip")
	local questHasteEnabled = gossipDB and gossipDB.profile and gossipDB.profile.questHaste

	Automaton:RegisterDefaults("Quest", "profile", {
		disabled = true,
	})

	if questHasteEnabled then
		self.db.profile.disabled = false
	else
		Automaton:SetDisabledAsDefault(self, "Quest")
	end

	self:RegisterOptions(self.options)
end

function Automaton_Quest:OnEnable()
	self:RegisterEvent("GOSSIP_SHOW")
	self:RegisterEvent("QUEST_PROGRESS")
	self:RegisterEvent("QUEST_COMPLETE")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_GREETING")
end

function Automaton_Quest:OnDisable()
	self:UnregisterAllEvents()
end

------------------------------
--      Event Handlers      --
------------------------------

function Automaton_Quest:GOSSIP_SHOW()
	if IsShiftKeyDown() then return end

	self:QuestHasteGossip()
end

function Automaton_Quest:QUEST_GREETING()
	if IsShiftKeyDown() then return end

	local available = {}
	local active = {}

	for k = 1, GetNumAvailableQuests() do
		tinsert(available, {GetAvailableTitle(k), k})
	end
	for k = 1, GetNumActiveQuests() do
		tinsert(active, {GetActiveTitle(k), k})
	end

	self:QuestHasteSelectQuest(available, active, SelectAvailableQuest, SelectActiveQuest)
end

function Automaton_Quest:QUEST_DETAIL()
	if IsShiftKeyDown() then return end

	AcceptQuest()
end

function Automaton_Quest:QUEST_PROGRESS()
	if IsShiftKeyDown() then return end

	if IsQuestCompletable() then
		CompleteQuest()
	end
end

function Automaton_Quest:QUEST_COMPLETE()
	if IsShiftKeyDown() then return end

	self:QuestHasteCompleteReward()
end

function Automaton_Quest:QuestHasteGossip()
	if self:QuestHasteSelectQuest(self:ProcessAnyQuests(GetGossipAvailableQuests()), self:ProcessAnyQuests(GetGossipActiveQuests()), SelectGossipAvailableQuest, SelectGossipActiveQuest) then
		return true
	end
	return false
end

function Automaton_Quest:ProcessAnyQuests(...)
	local quests = {}
	for i = 1, table.getn(arg), 3 do
		local title = arg[i]
		if title then
			tinsert(quests, {title, (i+2)/3})
		end
	end
	return quests
end

function Automaton_Quest:GetCompletedQuestLogTitles()
	local completed = {}
	for k = 1, GetNumQuestLogEntries() do
		local title, level, tag, group, header, isComplete = GetQuestLogTitle(k)
		if title and isComplete then
			completed[title] = true
		end
	end
	return completed
end

function Automaton_Quest:QuestHasteSelectQuest(available, active, accept, complete)
	local completed = self:GetCompletedQuestLogTitles()

	for k = 1, table.getn(active) do
		local quest = active[k]
		if completed[quest[1]] then
			complete(quest[2])
			return true
		end
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

function Automaton_Quest:QuestHasteCompleteReward()
	local choices = GetNumQuestChoices()
	if choices == 0 then
		GetQuestReward()
	elseif choices == 1 then
		GetQuestReward(1)
	end
end
