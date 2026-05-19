assert(Automaton, "Automaton not found!")

------------------------------
--      Are you local?      --
------------------------------

local L = AceLibrary("AceLocale-2.2"):new("Automaton_Gossip")
local GossipData = {}

local function IsQuestAutomationEnabled()
	return Automaton:HasModule("Quest") and Automaton:IsModuleActive("Quest")
end

----------------------------------
--      Module Declaration      --
----------------------------------

Automaton_Gossip = Automaton:NewModule("Gossip")
Automaton_Gossip.modulename = L["Gossip"]
Automaton_Gossip.moduledesc = L["Automatically skip gossip text"]
Automaton_Gossip.options = {}

------------------------------
--      Initialization      --
------------------------------

function Automaton_Gossip:OnInitialize()
	self.db = Automaton:AcquireDBNamespace("Gossip")
	Automaton:RegisterDefaults("Gossip", "profile", {})

	GossipData = Automaton_Gossip:GetGossipData()

	self:RegisterOptions(self.options)
end

function Automaton_Gossip:OnEnable()
	self:RegisterEvent("GOSSIP_SHOW")
end

function Automaton_Gossip:OnDisable()
	self:UnregisterAllEvents()
end

------------------------------
--      Event Handlers      --
------------------------------

function Automaton_Gossip:GOSSIP_SHOW()
	if IsShiftKeyDown() then return end

	if IsQuestAutomationEnabled() then
		local z,_ = GetGossipAvailableQuests()
		local x,_ = GetGossipActiveQuests()
		if x or z then
			return
		end
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
