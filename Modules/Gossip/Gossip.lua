assert(Automaton, "Automaton not found!")

------------------------------
--      Are you local?      --
------------------------------

local L = AceLibrary("AceLocale-2.2"):new("Automaton_Gossip")
local GossipData = {}
local QuestData = {}
local ServiceGossipTypes = {"trainer", "vendor", "banker", "taxi", "battlemaster", "healer", "petition", "tabard", "workorder"}
local UnsafeGossipTypes = {
	["binder"] = true,
	["unlearn"] = true,
}
local CityDirectionGossipPatterns = {
	"direction",
	"auction house",
	"bank",
	"battlemaster",
	"class trainer",
	"flight master",
	"gryphon master",
	"guild master",
	"inn",
	"mailbox",
	"profession trainer",
	"stable master",
	"weapon master",
	"wind rider master",
	"zeppelin",
	"deeprun tram",
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

local function NormalizeQuestTitle(title)
	if not title then
		return nil
	end
	title = string.gsub(title, "|c%x%x%x%x%x%x%x%x", "")
	title = string.gsub(title, "|r", "")
	title = string.gsub(title, "^%s+", "")
	title = string.gsub(title, "%s+$", "")
	return title
end

local function GetItemNameFromLink(link)
	if not link then
		return nil
	end

	local item = GetItemInfo(link)
	if item then
		return item
	end

	local _, _, linkedName = string.find(link, "%[(.-)%]")
	return linkedName
end

local function GetGossipQuestCompleteValue(values, index, stride)
	if stride == 2 and type(values[index+1]) == "boolean" then
		return values[index+1]
	end

	if stride >= 4 then
		return values[index+3]
	end

	return values[index+2]
end

local function GetOddIndexedValues(values)
	local result = {}
	values = values or {}
	for k = 1, table.getn(values) do
		if math.mod(k, 2) ~= 0 then
			tinsert(result, values[k])
		end
	end
	return result
end

----------------------------------
--      Module Declaration      --
----------------------------------

Automaton_Gossip = Automaton:NewModule("Gossip")
Automaton_Gossip.modulename = L["Gossip & Quest"]
Automaton_Gossip.moduledesc = L["Automatically complete quests and skip gossip text"]
Automaton_Gossip.options = {
	gossipHaste = {
		order = 2,
		type = "toggle",
		name = L["Gossip"],
		desc = "Automatically navigate safe gossip and service options. Hold Shift to pause automation.",
		get = function() return Automaton_Gossip.db.profile.gossipHaste end,
		set = function(v) Automaton_Gossip.db.profile.gossipHaste = v end,
	},
	questHaste = {
		order = 3,
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
		gossipHaste = true,
		questHaste = false,
		bankItems = {},
	})

	GossipData = Automaton_Gossip:GetGossipData()
	QuestData = Automaton_Gossip:GetQuestData()

	self:RegisterOptions(self.options)
	self.options.enabled.name = L["Enabled"]
	self.options.debugging.name = L["Debug"]
end

function Automaton_Gossip:OnEnable()
	self:RegisterEvent("GOSSIP_SHOW")
	self:RegisterEvent("QUEST_PROGRESS")
	self:RegisterEvent("QUEST_COMPLETE")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_GREETING")
	self:RegisterEvent("BANKFRAME_OPENED", "ScanBankItems")
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "ScanBankItemsIfOpen")
	self:RegisterEvent("BAG_UPDATE", "ScanBankItemsIfOpen")
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
	local activeQuests = self:GetGossipActiveQuestOptions()
	local availableQuests = self:GetGossipAvailableQuestOptions()
	self:Debug("GOSSIP_SHOW: "..gossipCount.." gossip options.")

	if self.db.profile.questHaste and self:QuestHasteGossip(activeQuests, availableQuests, gossipCount, gossipOptions) then
		self:Debug("Quest automation handled gossip event.")
		return
	end

	if not self.db.profile.gossipHaste then
		return
	end

	if self:ShouldPauseGossipForQuestOptions(activeQuests, availableQuests) then
		return
	end

	self:RunGossipAutomation(gossipCount, gossipOptions)
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

function Automaton_Gossip:GetGossipQuestOptions(counter, getter, preferredStride, hasCompleteValue)
	local values = {}
	if getter then
		values = { getter() }
	end

	local quests = {}
	local max = self:GetMaxTableIndex(values)
	local stride = preferredStride or 3
	local count
	if counter then
		count = counter() or 0
	end

	if count and count > 0 and max > 0 then
		local inferredStride = max / count
		if inferredStride == math.floor(inferredStride) and inferredStride >= 2 then
			stride = inferredStride
		end
	else
		if type(values[3]) == "string" then
			stride = 2
		elseif type(values[4]) == "string" then
			stride = 3
		elseif type(values[5]) == "string" then
			stride = 4
		end
	end

	if not count or count == 0 then
		count = 0
		while values[count*stride + 1] do
			count = count + 1
		end
	end

	for optionIndex = 1, count do
		local k = (optionIndex-1)*stride + 1
		local title = values[k]
		if type(title) == "string" then
			local completeValue = nil
			if hasCompleteValue then
				completeValue = GetGossipQuestCompleteValue(values, k, stride)
			end
			tinsert(quests, {NormalizeQuestTitle(title), optionIndex, completeValue, values[k+1]})
		end
	end
	return quests
end

function Automaton_Gossip:GetGossipAvailableQuestOptions()
	return self:GetGossipQuestOptions(GetNumGossipAvailableQuests, GetGossipAvailableQuests, 3, false)
end

function Automaton_Gossip:GetGossipActiveQuestOptions()
	return self:GetGossipQuestOptions(GetNumGossipActiveQuests, GetGossipActiveQuests, 4, true)
end

function Automaton_Gossip:GetQuestHasteGossipQuestTitles(getter)
	local values = {}
	if getter then
		values = { getter() }
	end

	local titles = {}
	local oddValues = GetOddIndexedValues(values)
	for k = 1, table.getn(oddValues) do
		if type(oddValues[k]) == "string" then
			tinsert(titles, {NormalizeQuestTitle(oddValues[k]), k})
		end
	end
	return titles
end

function Automaton_Gossip:GetQuestHasteGossipAvailableQuestTitles()
	return self:GetGossipAvailableQuestOptions()
end

function Automaton_Gossip:GetQuestHasteGossipActiveQuestTitles()
	return self:GetGossipActiveQuestOptions()
end

function Automaton_Gossip:HasGossipQuests()
	return table.getn(self:GetGossipAvailableQuestOptions()) > 0 or table.getn(self:GetGossipActiveQuestOptions()) > 0
end

function Automaton_Gossip:SelectSingleGossipOption(title, gossipType)
	if gossipType then
		gossipType = string.lower(gossipType)
	end

	if self:IsUnsafeGossipType(gossipType) then
		self:Debug("Not selecting unsafe gossip option: "..tostring(title).." ("..tostring(gossipType)..")")
		return false
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

function Automaton_Gossip:HasGossipOptionByType(count, options, wantedType)
	options = options or {}
	count = count or table.getn(options) / 2
	for k = 1, count do
		local i = (k-1)*2 + 1
		local title, gossipType = options[i], self:NormalizeGossipType(options[i+1])
		if title and gossipType == wantedType then
			return true
		end
	end
	return false
end

function Automaton_Gossip:HasGossipOptionMatching(count, options, patterns)
	options = options or {}
	count = count or table.getn(options) / 2
	for k = 1, count do
		local i = (k-1)*2 + 1
		local title = options[i]
		if title then
			title = string.lower(title)
			for j = 1, table.getn(patterns) do
				if string.find(title, patterns[j]) then
					return true
				end
			end
		end
	end
	return false
end

function Automaton_Gossip:HasInnkeeperGossip(count, options)
	return self:HasGossipOptionByType(count, options, "binder")
end

function Automaton_Gossip:HasCityDirectionGossip(count, options)
	if self:HasGossipOptionByType(count, options, "gossip") and self:HasGossipOptionMatching(count, options, CityDirectionGossipPatterns) then
		return true
	end
	return false
end

function Automaton_Gossip:HasQuestOptions(active, available)
	active = active or {}
	available = available or {}
	return table.getn(active) > 0 or table.getn(available) > 0
end

function Automaton_Gossip:ShouldPauseGossipForQuestOptions(active, available)
	if self.db.profile.questHaste then
		return self:HasQuestOptions(active, available)
	end

	if self:HasQuestOptions(active, available) then
		self:Debug("Quest options present; gossip automation paused.")
		return true
	end

	return false
end

function Automaton_Gossip:SelectFirstServiceGossip(count, options)
	for k = 1, table.getn(ServiceGossipTypes) do
		if self:SelectGossipOptionByType(count, options, ServiceGossipTypes[k]) then
			return true
		end
	end
	return false
end

function Automaton_Gossip:RunGossipAutomation(count, options)
	options = options or {}
	count = count or table.getn(options) / 2

	if count == 0 then
		return false
	end

	if self:HasInnkeeperGossip(count, options) then
		self:Debug("Innkeeper gossip detected; automation paused.")
		return false
	end

	if self:HasCityDirectionGossip(count, options) then
		self:Debug("City direction gossip detected; automation paused.")
		return false
	end

	if self:SelectFirstServiceGossip(count, options) then
		return true
	end

	if count == 1 then
		return self:SelectSingleGossipOption(options[1], options[2])
	end

	local g = self:ProcessGossip(count, options)
	if self:SelectGossip(g, true) then
		return true
	end

	return self:SelectGossip(g)
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
		tinsert(available, {NormalizeQuestTitle(GetAvailableTitle(k)), k})
	end
	for k = 1, GetNumActiveQuests() do
		local title, isComplete = GetActiveTitle(k)
		tinsert(active, {NormalizeQuestTitle(title), k, isComplete})
	end

	self:QuestHasteSelectQuest(active, available, SelectActiveQuest, SelectAvailableQuest)
end

function Automaton_Gossip:QUEST_DETAIL()
	if not self.db.profile.questHaste or IsShiftKeyDown() then return end
	AcceptQuest()
end

function Automaton_Gossip:QUEST_PROGRESS()
	if not self.db.profile.questHaste or IsShiftKeyDown() then return end
	if IsQuestCompletable() then
		CompleteQuest()
	else
		local title = NormalizeQuestTitle(GetTitleText())
		local completed = self:GetQuestLogCompletionMap()
		if title and completed[title] and not self:HasRequiredQuestItems(title) then
			self:NotifyBankItemsForQuest(title)
		end
	end
end

function Automaton_Gossip:QUEST_COMPLETE()
	if not self.db.profile.questHaste or IsShiftKeyDown() then return end
	self:QuestHasteCompleteReward()
end

function Automaton_Gossip:QuestHasteGossip(active, available, gossipCount, gossipOptions)
	active = active or self:GetGossipActiveQuestOptions()
	available = available or self:GetGossipAvailableQuestOptions()
	if self:QuestHasteSelectQuest(active, available, SelectGossipActiveQuest, SelectGossipAvailableQuest, gossipCount, gossipOptions) then
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
	if type(fourth) == "number" then
		if seventh ~= nil then
			return title, fifth, sixth, seventh
		end
		return title, fifth, nil, sixth
	end
	if seventh ~= nil then
		return title, fifth, sixth, seventh
	end
	return title, fourth, fifth, sixth
end

function Automaton_Gossip:IsCompleteValue(value)
	if value == true or value == 1 then
		return true
	end

	if type(value) == "string" then
		value = string.lower(value)
		return value == "1" or value == "true" or value == "complete" or value == "completed"
	end

	return false
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
	title = NormalizeQuestTitle(title)
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

function Automaton_Gossip:GetBankContainers()
	local containers = { BANK_CONTAINER or -1 }
	local firstBankBag = (NUM_BAG_SLOTS or 4) + 1
	local lastBankBag = firstBankBag + (NUM_BANKBAGSLOTS or 6) - 1
	for bag = firstBankBag, lastBankBag do
		tinsert(containers, bag)
	end
	return containers
end

function Automaton_Gossip:GetContainerItemDetails(bag, slot)
	local link = GetContainerItemLink(bag, slot)
	if not link then
		return nil
	end

	local item = GetItemNameFromLink(link)
	if not item then
		return nil
	end

	local texture, quantity = GetContainerItemInfo(bag, slot)
	return item, link, quantity or 1
end

function Automaton_Gossip:ScanBankItems()
	local bankItems = {}
	local containers = self:GetBankContainers()
	for k = 1, table.getn(containers) do
		local bag = containers[k]
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local item, link, quantity = self:GetContainerItemDetails(bag, slot)
			if item then
				if not bankItems[item] then
					bankItems[item] = { link = link, quantity = 0 }
				end
				bankItems[item].quantity = bankItems[item].quantity + quantity
				if link then
					bankItems[item].link = link
				end
			end
		end
	end

	self.db.profile.bankItems = bankItems
end

function Automaton_Gossip:ScanBankItemsIfOpen()
	if BankFrame and BankFrame:IsVisible() then
		self:ScanBankItems()
	end
end

function Automaton_Gossip:FindBankItem(itemname)
	local cached = self.db.profile.bankItems and self.db.profile.bankItems[itemname]
	if cached and cached.quantity and cached.quantity > 0 then
		return cached
	end

	return nil
end

function Automaton_Gossip:NotifyItemInBank(item)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(tostring(item).." is in your bank!", 1, 0, 0)
	end
	PlaySound("igQuestFailed")
end

function Automaton_Gossip:NotifyBankItemsForItems(items)
	local warned = false
	if not items then
		return warned
	end

	for item, quantity in pairs(items) do
		local inBags = tonumber(self:SearchBagsForQuantity(item)) or 0
		if inBags < quantity then
			local bankItem = self:FindBankItem(item)
			if bankItem then
				self:NotifyItemInBank(bankItem.link or item)
				warned = true
			end
		end
	end

	return warned
end

function Automaton_Gossip:NotifyBankItemsForQuest(title)
	title = NormalizeQuestTitle(title)
	local data = QuestData[title]
	if not data then
		return false
	end

	local warned = self:NotifyBankItemsForItems(data.items)
	local faction = UnitFactionGroup("player")
	if faction and self:NotifyBankItemsForItems(data[faction]) then
		warned = true
	end

	return warned
end

function Automaton_Gossip:IsQuestLogEntryComplete(index, title, isHeader, isComplete)
	if not title or isHeader then
		return false
	end

	if self:IsCompleteValue(isComplete) then
		return true
	end

	if not GetNumQuestLeaderBoards or not GetQuestLogLeaderBoard then
		return false
	end

	local objectives = GetNumQuestLeaderBoards(index) or 0
	if objectives == 0 then
		return false
	end

	for k = 1, objectives do
		local text, objectiveType, finished = GetQuestLogLeaderBoard(k, index)
		if text and not self:IsCompleteValue(finished) then
			return false
		end
	end

	return true
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
			title = NormalizeQuestTitle(title)
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

function Automaton_Gossip:GetQuestHasteCompletedQuestLogTitles()
	local completed = {}
	for k = 1, GetNumQuestLogEntries() do
		local title, isHeader, isCollapsed, isComplete = self:GetQuestLogEntryInfo(k)
		title = NormalizeQuestTitle(title)
		if title and not isHeader and self:IsCompleteValue(isComplete) then
			completed[title] = true
		end
	end
	return completed
end

function Automaton_Gossip:IsActiveQuestCompletable(quest, completed, known, completeValue)
	local title = NormalizeQuestTitle(quest and quest[1])
	if not title then
		return false
	end

	if not self:IsActiveQuestObjectivesComplete(quest, completed, known, completeValue) then
		return false
	end

	return self:HasRequiredQuestItems(title)
end

function Automaton_Gossip:IsActiveQuestObjectivesComplete(quest, completed, known, completeValue)
	local title = NormalizeQuestTitle(quest and quest[1])
	if not title then
		return false
	end

	if completeValue == nil and quest then
		completeValue = quest[3]
	end

	if self:IsCompleteValue(completeValue) then
		return true
	end

	return completed and completed[title]
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

function Automaton_Gossip:QuestHasteSelectActiveQuest(active, complete, completed, known)
	active = active or {}
	for k = 1, table.getn(active) do
		local quest = active[k]
		if self:IsActiveQuestCompletable(quest, completed, known) then
			complete(quest[2])
			return true
		elseif self:IsActiveQuestObjectivesComplete(quest, completed, known) then
			self:NotifyBankItemsForQuest(quest[1])
		end
	end

	return false
end

function Automaton_Gossip:QuestHasteSelectCompletedGossipOption(count, options, completed)
	options = options or {}
	count = count or table.getn(options) / 2
	for k = 1, count do
		local i = (k-1)*2 + 1
		local title = NormalizeQuestTitle(options[i])
		if title and completed and completed[title] then
			if self:HasRequiredQuestItems(title) then
				self:Debug("AutoQuestGossip: "..title)
				SelectGossipOption(k)
				return true
			end
			self:NotifyBankItemsForQuest(title)
		end
	end

	return false
end

function Automaton_Gossip:QuestHasteAcceptAvailableQuest(available, accept)
	available = available or {}
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

function Automaton_Gossip:QuestHasteSelectFirstActiveQuest(active, complete)
	active = active or {}
	if table.getn(active) > 0 then
		self:Debug("AutoActiveQuest fallback: "..tostring(active[1][1]))
		complete(active[1][2])
		return true
	end

	return false
end

function Automaton_Gossip:QuestHasteSelectQuest(active, available, complete, accept, gossipCount, gossipOptions)
	local completed = self:GetQuestHasteCompletedQuestLogTitles()
	local known = nil

	if self:QuestHasteSelectActiveQuest(active, complete, completed, known) then
		return true
	end

	if self:QuestHasteSelectCompletedGossipOption(gossipCount, gossipOptions, completed) then
		return true
	end

	if self:QuestHasteAcceptAvailableQuest(available, accept) then
		return true
	end

	return self:QuestHasteSelectFirstActiveQuest(active, complete)
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
		if self:IsUnsafeGossipType(gossipType) then
			self:Debug("Skipping unsafe gossip option: "..tostring(title).." ("..tostring(gossipType)..")")
		elseif gossipType == "gossip" then
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
		local title = NormalizeQuestTitle(quest[1])
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
		local title, level = NormalizeQuestTitle(values[i]), values[i+1]
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
		local slots = GetContainerNumSlots(bag) or 0
		if slots > 0 then
			for slot = 1, slots do
				local item, link, itemQuantity = self:GetContainerItemDetails(bag, slot)
				if item == itemname then
					quantity = quantity + itemQuantity
				end
			end
		end
	end
	return quantity
end
