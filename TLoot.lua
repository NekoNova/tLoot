-----------------------------------------------------------------------------------------------
-- Client Lua Script for TLoot
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "Sound"
 
-----------------------------------------------------------------------------------------------
-- TLoot Module Definition
-----------------------------------------------------------------------------------------------
local NAME = "tLoot"

local TLoot = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon(NAME, false, {"Gemini:Logging-1.2"})

local Logger
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
local ktVersion = {nMajor = 1, nMinor = 0, nPatch = 0}

local ktDefaultSettings = {
	tVersion = {
		nMajor = ktVersion.nMajor,
		nMinor = ktVersion.nMinor,
		nPatch = ktVersion.nPatch
	},
	tAnchorOffsets = {5, 446, 300, 480},
	tOptionsWindowPos = {},
	bAnchorVisible = true,
	nBarUpdateSpeed = 0.2,
	nBarHeight = 34,
	nBarWidth = 295,
	bBottomToTop = false,
	nNeedKeybind = 78, nGreedKeybind = 71, nPassKeybind = 80,
	bNeedKeybind = true, bGreedKeybind = true, bPassKeybind = false,
	sLogLevel = "DEBUG"
}

local ktEvalColors = {
	[Item.CodeEnumItemQuality.Inferior] 		= ApolloColor.new("ItemQuality_Inferior"),
	[Item.CodeEnumItemQuality.Average] 			= ApolloColor.new("ItemQuality_Average"),
	[Item.CodeEnumItemQuality.Good] 			= ApolloColor.new("ItemQuality_Good"),
	[Item.CodeEnumItemQuality.Excellent] 		= ApolloColor.new("ItemQuality_Excellent"),
	[Item.CodeEnumItemQuality.Superb] 			= ApolloColor.new("ItemQuality_Superb"),
	[Item.CodeEnumItemQuality.Legendary] 		= ApolloColor.new("ItemQuality_Legendary"),
	[Item.CodeEnumItemQuality.Artifact]		 	= ApolloColor.new("ItemQuality_Artifact")
}

local ktRollType = {
	["Need"] = 1,
	["Greed"] = 2,
	["Pass"] = 3
}

local ktKeys = {
	[16] = "SHIFT", [17] = "CTRL",
	[65] = "A", [66] = "B", [67] = "C", [68] = "D", [69] = "E", [70] = "F", [71] = "G", [72] = "H", [73] = "I", [74] = "J", [75] = "K", [76] = "L", [77] = "M",
	[78] = "N", [79] = "O", [80] = "P", [81] = "Q", [82] = "R", [83] = "S", [84] = "T", [85] = "U", [86] = "V", [87] = "W", [88] = "X", [89] = "Y", [90] = "Z",
	[96] = "0", [97] = "1", [98] = "2", [99] = "3", [100] = "4", [101] = "5", [102] = "6", [103] = "7", [104] = "8", [105] = "9"
}

local knLootRollTime = 60000
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function TLoot:OnInitialize()
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	Logger = GeminiLogging:GetLogger({
		level = GeminiLogging.ERROR,
		pattern = "%d [%c:%n] %l - %m",
		appender = "GeminiConsole"
	})
	Logger:debug("Logger Initialized")
	
	self.settings = copyTable(ktDefaultSettings)
	
	self.xmlDoc = XmlDoc.CreateFromFile("TLoot.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

function TLoot:OnSave(eLevel)
	if (eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character) then
		return
	end
	Logger:debug("OnSaveSettings")
	
	self.settings.tVersion = copyTable(tVersion)
	
	return self.settings
end

function TLoot:OnRestore(eLevel, tData)
	Logger:debug("OnRestoreSettings")
	if tData ~= nil then
		self.settings = mergeTables(self.settings, tData)
		Logger:SetLevel(self.settings.sLogLevel)
	end
end

function TLoot:OnSlashCommand(strCommand, strParam)
	if strParam then
		if strParam == "options" then
			self:ToggleOptionsWindow()
			
			return
		elseif string.sub(strParam, 1, string.len("loglevel")) == "loglevel" then
			self.settings.sLogLevel = string.upper(string.sub(strParam, string.len("loglevel") + 2))
			Logger:SetLevel(self.settings.sLogLevel)
			
			return
		end
	end
	self:ToggleAnchor()
end

function TLoot:OnDocLoaded()
	Logger:debug("OnDocLoaded (loaded = %s)", tostring(self.xmlDoc:IsLoaded()))
	if self.xmlDoc == nil and self.xmlDoc:IsLoaded() then
		Logger:error("Document not Loaded")
		return
	end
	
	Apollo.RegisterEventHandler("LootRollUpdate",		"OnGroupLoot", self)
    Apollo.RegisterTimerHandler("LootUpdateTimer", 		"OnUpdateTimer", self)
    Apollo.RegisterEventHandler("LootRollWon", 			"OnLootRollWon", self)
    Apollo.RegisterEventHandler("LootRollAllPassed", 	"OnLootRollAllPassed", self)
	
	Apollo.RegisterEventHandler("LootRollSelected", 	"OnLootRollSelected", self)
	Apollo.RegisterEventHandler("LootRollPassed", 		"OnLootRollPassed", self)
	Apollo.RegisterEventHandler("LootRoll", 			"OnLootRoll", self)
	
	Apollo.CreateTimer("LootUpdateTimer", self.settings.nBarUpdateSpeed, false)
	Apollo.StopTimer("LootUpdateTimer")
	self.bTimerRunning = false
	
	self.wndAnchor = Apollo.LoadForm(self.xmlDoc, "AnchorForm", nil, self)
	self.wndAnchor:SetAnchorOffsets(unpack(self.settings.tAnchorOffsets))
	self.wndAnchor:FindChild("Header"):Show(self.settings.bAnchorVisible)
	
	Apollo.RegisterSlashCommand("tLoot", "OnSlashCommand", self)
	Apollo.RegisterSlashCommand("tloot", "OnSlashCommand", self)
	Apollo.RegisterSlashCommand("tl", "OnSlashCommand", self)
	
	Apollo.RegisterEventHandler("SystemKeyDown", "OnSystemKeyDown", self)
	
	self.tLootRolls = nil
	self.tKnownLoot = nil
	self.tRollData = {}
	self.tCompletedRolls = {}
	
	if GameLib.GetLootRolls() then
		self:OnGroupLoot()
	end
end

-----------------------------------------------------------------------------------------------
-- TLoot Functions
-----------------------------------------------------------------------------------------------
function TLoot:ToggleAnchor()
	if self.wndAnchor then
		self.settings.bAnchorVisible = not self.settings.bAnchorVisible
		self.wndAnchor:FindChild("Header"):Show(self.settings.bAnchorVisible)
	end
end

function TLoot:SetBarValue(wndBar, fMin, fValue, fMax)
	wndBar:SetMax(fMax)
	wndBar:SetFloor(fMin)
	wndBar:SetProgress(fValue)
end


-----------------------------------------------------------------------------------------------
-- TLootForm Functions
-----------------------------------------------------------------------------------------------
function TLoot:OnAnchorMove(wndHandler, wndControl, nOldLeft, nOldTop, nOldRight, nOldBottom)
	self.settings.tAnchorOffsets = {self.wndAnchor:GetAnchorOffsets()}
end

function TLoot:ToggleRollButtons(wndItemContainer, bNeed, bGreed, bPass)
	Logger:debug("ToggleRollButtons (N=%s,G=%s,P=%s)", tostring(bNeed), tostring(bGreed), tostring(bPass))
	local needBtn = wndItemContainer:FindChild("NeedBtn")
	local greedBtn = wndItemContainer:FindChild("GreedBtn")
	local passBtn = wndItemContainer:FindChild("PassBtn")
	
	needBtn:FindChild("DisableMask"):Show(not bNeed)
	needBtn:FindChild("DisableMask"):SetBGColor({a = 0.5, r = 0, g = 0, b = 0})
	greedBtn:FindChild("DisableMask"):Show(not bGreed)
	greedBtn:FindChild("DisableMask"):SetBGColor({a = 0.5, r = 0, g = 0, b = 0})
	passBtn:FindChild("DisableMask"):Show(not bPass)
	passBtn:FindChild("DisableMask"):SetBGColor({a = 0.5, r = 0, g = 0, b = 0})
end

function TLoot:GetLootWindowForRoll(tLootRoll)
	local wndAnchor = self.wndAnchor:FindChild("Anchor")
	local wndItemContainer = nil
	for idx, wndChild in ipairs(wndAnchor:GetChildren()) do
		local data = wndChild:GetData()
		
		if data and data.nLootId and tLootRoll.nLootId == data.nLootId then
			if wndItemContainer ~= nil then
				Logger:warn("GetLootWindowForRoll found multiple children with the same nLootId (%s)", tostring(tLootRoll.nLootId))
			end
			wndItemContainer = wndChild
		end
	end
	return wndItemContainer
end

function TLoot:GetLootWindowForItem(tItem)
	local wndAnchor = self.wndAnchor:FindChild("Anchor")
	local wndItemContainer = nil
	for idx, wndChild in ipairs(wndAnchor:GetChildren()) do
		local data = wndChild:GetData()
		
		if data and data.itemDrop and data.itemDrop:GetName() == tItem:GetName() then
			if wndItemContainer ~= nil then
				Logger:warn("GetLootWindowForItem found multiple children with the same name (%s)", tLootRoll:GetName())
			end
			wndItemContainer = wndChild
		end
	end
	return wndItemContainer
end

function TLoot:HelperBuildItemTooltip(wndArg, tItem, tModData, tGlyphData)
	wndArg:SetTooltipDoc(nil)
	wndArg:SetTooltipDocSecondary(nil)
	local itemEquipped = tItem:GetEquippedItemForItemType()
	Tooltip.GetItemTooltipForm(self, wndArg, tItem, {bPrimary = true, bSelling = false, itemCompare = itemEquipped, itemModData = tModData, tGlyphData = tGlyphData})
end

function TLoot:RemoveCompletedRolls()
	local wndAnchor = self.wndAnchor:FindChild("Anchor")
	for idx, wndItemContainer in ipairs(wndAnchor:GetChildren()) do
		local data = wndItemContainer:GetData()
		if not data or not data.nLootId or not self.tKnownLoot or not self.tKnownLoot[data.nLootId] then
			wndItemContainer:Destroy()
		end
	end
end

function TLoot:ResizeAllBars(nWidth, nHeight)
	if not self.wndAnchor then
		return
	end
	local wndAnchor = self.wndAnchor:FindChild("Anchor")
	if not wndAnchor then
		return
	end
	local children = wndAnchor:GetChildren()
	if not children then
		return
	end
	
	self:ResizeBar(self.wndAnchor, nWidth)
	self.settings.tAnchorOffsets = {self.wndAnchor:GetAnchorOffsets()}
	for idx, child in ipairs(children) do
		self:ResizeBar(child, nWidth, nHeight)
	end
	wndAnchor:ArrangeChildrenVert()
end

function TLoot:ResizeBar(wndItemContainer, nWidth, nHeight)
	if not wndItemContainer then
		return
	end
	
	local nLeft, nTop, nRight, nBottom = wndItemContainer:GetAnchorOffsets()
	if nWidth == nil then
		nWidth = (nRight - nLeft)
	end
	if nHeight == nil then
		nHeight = (nBottom - nTop)
	end
	wndItemContainer:SetAnchorOffsets(nLeft, nTop, nLeft + nWidth, nTop + nHeight)
end

-----------------------------------------------------------------------------------------------
-- Update/Draw Functions
-----------------------------------------------------------------------------------------------
function TLoot:OnGroupLoot()
	Logger:debug("OnGroupLoot (running = %s)", tostring(self.bTimerRunning))
	if not self.bTimerRunning then
		Apollo.StartTimer("LootUpdateTimer")
		self.bTimerRunning = true
	end
end

function TLoot:UpdateKnownLoot()
	Logger:debug("UpdateKnownLoot")
	self.tLootRolls = GameLib.GetLootRolls()
	if (not self.tLootRolls or #self.tLootRolls == 0) then
		Logger:debug("No loot rolls")
		self.tLootRolls = nil
		self.tKnownLoot = nil
		return
	end
	
	self.tKnownLoot = {}
	if self.tLootRolls and #self.tLootRolls > 0 then
		for idx, tLootRoll in ipairs(self.tLootRolls) do
			self.tKnownLoot[tLootRoll.nLootId] = tLootRoll 
		end
	end
end

function TLoot:OnUpdateTimer()
	self:UpdateKnownLoot()
	
	Logger:debug("OnUpdateTimer (%s rolls)", (self.tKnownLoot and tostring(#self.tKnownLoot) or "0"))
	if self.tKnownLoot then
		for nLootId, tLootRoll in pairs(self.tKnownLoot) do
			self:DrawLoot(tLootRoll)
		end
	end
	
	self:RemoveCompletedRolls()

	if self.tLootRolls and #self.tLootRolls > 0 then
		Logger:debug("Restarting Timer")
		Apollo.StartTimer("LootUpdateTimer")
	else
		Logger:debug("Timer Stopped")
		self.bTimerRunning = false
	end
end

function TLoot:DrawLoot(tLootRoll)
	Logger:debug("DrawLoot")
	if not self.wndAnchor or not self.wndAnchor:IsValid() then
		Logger:error("Anchor doesn't exist or is not valid")
		return
	end
	
	local wndAnchor = self.wndAnchor:FindChild("Anchor")
	local wndItemContainer = self:GetLootWindowForRoll(tLootRoll)
	local bFirstRun = false
	
	if wndItemContainer == nil then
		Logger:debug("New Container (Id=%s,N=%s)", tostring(tLootRoll.nLootId), tLootRoll.itemDrop:GetName())
		bFirstRun = true
		wndItemContainer = Apollo.LoadForm(self.xmlDoc, "ItemForm", wndAnchor, self)
		self:ResizeBar(wndItemContainer, self.settings.nWidth, self.settings.nHeight)
		wndAnchor:ArrangeChildrenVert()
		wndAnchor:EnsureChildVisible(wndItemContainer)
		Sound.Play(Sound.PlayUIWindowNeedVsGreedOpen)
	end
	wndItemContainer:SetData(tLootRoll)
	
	local itemCurrent = tLootRoll.itemDrop
	local itemName = itemCurrent:GetName()
	local itemQualityColor = ktEvalColors[itemCurrent:GetItemQuality()]
	local itemModData = tLootRoll.tModData
	local tGlyphData = tLootRoll.tSigilData
	if bFirstRun then
		-- This stuff shouldn't change
		wndItemContainer:FindChild("Name"):SetText(itemName)
		wndItemContainer:FindChild("Name"):SetTextColor(itemQualityColor)
		wndItemContainer:FindChild("IconFrame"):SetBGColor(itemQualityColor)
		wndItemContainer:FindChild("BarFrame"):SetBGColor(itemQualityColor)
		if wndItemContainer:FindChild("TimeRemainingBar").SetBarColor then
			wndItemContainer:FindChild("TimeRemainingBar"):SetBarColor(itemQualityColor)
		else
			Logger:debug("Nope!!!!!!!!!!!!!!!!!!!!!!!!!")
			Logger:debug(wndItemContainer:FindChild("TimeRemainingBar"))
		end
		wndItemContainer:FindChild("Icon"):SetSprite(itemCurrent:GetIcon())
	
		self:HelperBuildItemTooltip(wndItemContainer, itemCurrent, itemModData, tGlyphData)
	end
	
	local btnNeed = wndItemContainer:FindChild("NeedBtn")
	local btnGreed = wndItemContainer:FindChild("GreedBtn")
	local btnPass = wndItemContainer:FindChild("PassBtn")
	self:ToggleRollButtons(wndItemContainer,
		(btnNeed:GetData() == nil or btnNeed:GetData() == true) and GameLib.IsNeedRollAllowed(tLootRoll.nLootId),
		(btnGreed:GetData() == nil or btnGreed:GetData() == true),
		(btnPass:GetData() == nil or btnPass:GetData() == true)
	)
	
	local needCount, greedCount, passCount = 0, 0, 0
	local needTooltip, greedTooltip, passTooltip = "", "", ""
	if self.tRollData and self.tRollData[itemCurrent:GetItemId()] then
		local tItemRoll = self.tRollData[itemCurrent:GetItemId()]
		for player, rolltype in pairs(tItemRoll.players) do
			local nRoll = tItemRoll.rolls[player]
			local bWinner = tItemRoll.sWinner and tItemRoll.sWinner == player
			local sTooltip = "<P TextColor=\"" .. (bWinner and "green" or "white") .. "\">" .. player .. (nRoll ~= nil and (" (" .. nRoll .. ")") or "") .. "</P>"
			if rolltype == ktRollType["Need"] then
				needCount = needCount + 1
				needTooltip = needTooltip .. sTooltip
			elseif rolltype == ktRollType["Greed"] then
				greedCount = greedCount + 1
				greedTooltip = greedTooltip .. sTooltip
			elseif rolltype == ktRollType["Pass"] then
				passCount = passCount + 1
				passTooltip = passTooltip .. sTooltip
			end
		end
		
		if needTooltip ~= "" then
			needTooltip = "<P>------</P>" .. needToolTip
		end
		if greedTooltip ~= "" then
			greedTooltip = "<P>------</P>" .. greedToolTip
		end
		if passTooltip ~= "" then
			passTooltip = "<P>------</P>" .. passToolTip
		end
	end
	needTooltip = "<P>" .. Apollo.GetString("CRB_Need") .. "</P>" .. needTooltip
	greedTooltip = "<P>" .. Apollo.GetString("CRB_Greed") .. "</P>" .. greedTooltip
	passTooltip = "<P>" .. Apollo.GetString("CRB_Pass") .. "</P>" .. passTooltip
	btnNeed:SetText(needCount)
	btnNeed:SetTooltip(needTooltip)
	btnGreed:SetText(greedCount)
	btnGreed:SetTooltip(greedTooltip)
	btnPass:SetText(passCount)
	btnPass:SetTooltip(passTooltip)
	
	if tLootRoll.nTimeLeft > knLootRollTime then
		knLootRollTime = tLootRoll.nTimeLeft
	end
	self:SetBarValue(wndItemContainer:FindChild("TimeRemainingBar"), 0, tLootRoll.nTimeLeft, knLootRollTime)
end

-----------------------------------------------------------------------------------------------
-- Chat Message Events
-----------------------------------------------------------------------------------------------
function TLoot:AddItemRollType(tItem, sPlayer, nRollType)
	local nId = tItem:GetItemId()
	if not self.tRollData[nId] then
		self.tRollData[nId] = {
			players = {},
			rolls = {},
			winner = nil
		}
	end
	
	self.tRollData[nId].players[sPlayer] = nRollType
end

function TLoot:AddItemRoll(tItem, sPlayer, nRoll)
	local nId = tItem:GetItemId()
	if self.tRollData[nId] then
		self.tRollData[nId].rolls[sPlayer] = nRoll
	else
		Logger:error("Tried to add roll number without roll type") 
	end
end

function TLoot:AddItemWinner(tItem, sWinner)
	local nId = tItem:GetItemId()
	if self.tRollData[nId] then
		self.tRollData[nId].sWinner = sWinner
	else
		Logger:error("Tried to add roll winner without roll type")
	end
end

function TLoot:GetNeedOrGreedString(bNeed)
	if bNeed then
		return Apollo.GetString("NeedVsGreed_NeedRoll"), ktRollType["Need"]
	else
		return Apollo.GetString("NeedVsGreed_GreedRoll"), ktRollType["Greed"]
	end
end

function TLoot:OnLootRollAllPassed(tItem)
	Logger:debug("OnLootRollAllPassed (%s)", tItem:GetName())
	
	local wndItemContainer = self:GetLootWindowForItem(tItem)
	if wndItemContainer ~= nil then
		local data = wndItemContainer:GetData()
		data.nTimeCompleted = os.time() -- TODO: Need ms
		wndItemContainer:SetData(data)
	else
		Logger:warn("Could not find loot window for item %s", tItem:GetName())
	end
	
	ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Loot, String_GetWeaselString(Apollo.GetString("NeedVsGreed_EveryonePassed"), itemLooted:GetName()))
end

function TLoot:OnLootRollWon(tItem, sWinner, bNeed)
	Logger:debug("OnLootRollWon (i=%s, w=%s, n=%s)", tItem:GetName(), sWinner, tostring(bNeed))
	local sNeedOrGreed = self:GetNeedOrGreedString(bNeed)
	
	self:AddItemWinner(tItem, sWinner)
	local wndItemContainer = self:GetLootWindowForItem(tItem)
	if wndItemContainer ~= nil then
		local data = wndItemContainer:GetData()
		data.nTimeCompleted = os.time() -- TODO: Need ms
		wndItemContainer:SetData(data)
	else
		Logger:warn("Could not find loot window for item %s", tItem:GetName())
	end
	
	-- Example Message: Alvin used Greed Roll on Item Name for 45 (LootRoll).
	Event_FireGenericEvent("GenericEvent_LootChannelMessage", String_GetWeaselString(Apollo.GetString("NeedVsGreed_ItemWon"), sWinner, tItem:GetName(), sNeedOrGreed))
end

function TLoot:OnLootRollSelected(tItem, sPlayer, bNeed)
	Logger:debug("OnLootRollSelected (i=%s, p=%s, n=%s)", tItem:GetName(), sPlayer, tostring(bNeed))
	local sNeedOrGreed, nRollType = self:GetNeedOrGreedString(bNeed)
	
	self:AddItemRollType(tItem, sPlayer, nRollType)
	
	-- Example Message: strPlayer has selected to bNeed for nLootItem
	Event_FireGenericEvent("GenericEvent_LootChannelMessage", String_GetWeaselString(Apollo.GetString("NeedVsGreed_LootRollSelected"), sPlayer, sNeedOrGreed, tItem:GetName()))
end

function TLoot:OnLootRollPassed(tItem, sPlayer)
	Logger:debug("OnLootRollPassed (i=%s, p=%s)", tItem:GetName(), sPlayer)
	
	self:AddItemRollType(tItem, sPlayer, ktRollType["Pass"])
	
	-- Example Message: strPlayer passed on nLootItem
	Event_FireGenericEvent("GenericEvent_LootChannelMessage", String_GetWeaselString(Apollo.GetString("NeedVsGreed_PlayerPassed"), sPlayer, tItem:GetName()))
end

function TLoot:OnLootRoll(tItem, sPlayer, nRoll, bNeed)
	Logger:debug("OnLootRoll (i=%s, p=%s, r=%s, n=%s)", tItem:GetName(), sPlayer, tostring(nRoll), tostring(bNeed))
	local sNeedOrGreed, nRollType = self:GetNeedOrGreedString(bNeed)
	
	self:AddItemRoll(tItem, sPlayer, nRoll)
	
	-- Example String: strPlayer rolled nRoll for nLootItem (bNeed)
	Event_FireGenericEvent("GenericEvent_LootChannelMessage", String_GetWeaselString(Apollo.GetString("NeedVsGreed_OnLootRoll"), sPlayer, nRoll, tItem:GetName(), sNeedOrGreed ))
end

-----------------------------------------------------------------------------------------------
-- Buttons
-----------------------------------------------------------------------------------------------
function TLoot:Roll(wndItemContainer, nRollType)
	local data = wndItemContainer:GetData()
	
	if nRollType == ktRollType["Need"] then
		GameLib.RollOnLoot(data.nLootId, true)
	elseif nRollType == ktRollType["Greed"] then
		GameLib.RollOnLoot(data.nLootId, false)
	elseif nRollType == ktRollType["Pass"] then
		GameLib.PassOnLoot(data.nLootId)
	end
	
	data.nTimeRolled = os.time() -- TODO: Need ms
	self.tCompletedRolls[data.nLootId] = data
	wndItemContainer:SetData(data)
	self:ToggleRollButtons(wndItemContainer, false, false, false)
	
	wndItemContainer:Destroy()
end

function TLoot:OnSystemKeyDown(nKey)
	local children = self.wndAnchor:FindChild("Anchor"):GetChildren()
	
	if #children > 0 then
		local wndItemContainer = children[1]
		if self.settings.bNeedKeybind and nKey == self.settings.nNeedKeybind and not wndItemContainer:FindChild("NeedBtn"):FindChild("DisableMask"):IsVisible() then
			self:Roll(children[1], ktRollType["Need"])
		elseif self.settings.bGreedKeybind and nKey == self.settings.nGreedKeybind and not wndItemContainer:FindChild("GreedBtn"):FindChild("DisableMask"):IsVisible() then
			self:Roll(children[1], ktRollType["Greed"])
		elseif self.settings.bPassKeybind and nKey == self.settings.nPassKeybind and not wndItemContainer:FindChild("PassBtn"):FindChild("DisableMask"):IsVisible() then
			self:Roll(children[1], ktRollType["Pass"])
		end
	end
end

function TLoot:OnNeedBtn(wndHandler, wndControl)
	Logger:debug("OnNeedBtn")
	local wndItemContainer = wndHandler:GetParent():GetParent():GetParent()
	local data = wndItemContainer:GetData()
	
	if data and data.nLootId then
		self:Roll(wndItemContainer, ktRollType["Need"])
	else
		Logger:debug("No data to roll on")
	end
end

function TLoot:OnGreedBtn(wndHandler, wndControl)
	Logger:debug("OnGreedBtn")
	local wndItemContainer = wndHandler:GetParent():GetParent():GetParent()
	local data = wndItemContainer:GetData()
	
	if data and data.nLootId then
		self:Roll(wndItemContainer, ktRollType["Greed"])
	else
		Logger:debug("No data to roll on")
	end
end

function TLoot:OnPassBtn(wndHandler, wndControl)
	Logger:debug("OnPassBtn")
	local wndItemContainer = wndHandler:GetParent():GetParent():GetParent()
	local data = wndItemContainer:GetData()
	
	if data and data.nLootId then
		self:Roll(wndItemContainer, ktRollType["Pass"])
	else
		Logger:debug("No data to roll on")
	end
end

function TLoot:CustomButtonOnMouseOver(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	if wndHandler:FindChild("HoverMask") and not wndHandler:FindChild("DisableMask"):IsShown() then
		wndHandler:FindChild("HoverMask"):Show(true)
	end
end

function TLoot:CustomButtonOnMouseOut(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	if wndHandler:FindChild("HoverMask") then
		wndHandler:FindChild("HoverMask"):Show(false)
	end
end

-----------------------------------------------------------------------------------------------
-- Options Functions
-----------------------------------------------------------------------------------------------
function TLoot:ToggleOptionsWindow()
	self.bOptionsOpen = not self.bOptionsOpen
	Logger:debug("ToggleOptionsWindow (Open=%s)", tostring(self.bOptionsOpen))
	
	if not self.wndOptions then
		if not self.xmlDocOptions then
			self.xmlDocOptions = XmlDoc.CreateFromFile("Options.xml")
		end
		self.wndOptions = Apollo.LoadForm(self.xmlDocOptions, "OptionsForm", nil, self)
		self.wndOptionsList = Apollo.LoadForm(self.xmlDocOptions, "OptionsList", self.wndOptions:FindChild("ContentFrame"), self)
	end
	
	if self.bOptionsOpen then
		self:SetOptionValues()
		self.wndOptions:ToFront()
		local nScreenWidth, nScreenHeight = Apollo.GetScreenSize()
		local nLeft, nTop, nRight, nBottom = self.wndOptions:GetRect()
		local nWidth, nHeight = nRight - nLeft, nBottom - nTop
		
		if self.settings.tOptionsWindowPos[1] then
			self.wndOptions:Move(round(nScreenWidth * self.settings.tOptionsWindowPos[1]), round(nScreenHeight * self.settings.tOptionsWindowPos[2]), nWidth, nHeight)
		else
			self.wndOptions:Move(round((nScreenWidth / 2) - (nWidth / 2)), round((nScreenHeight / 2) - (nHeight / 2)), nWidth, nHeight)
		end
	end
	self.wndOptions:Show(self.bOptionsOpen, false)
end

function TLoot:OnOptionsWindowClosed(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	self:ToggleOptionsWindow()
end

function TLoot:OnOptionsWindowHide(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	if self.wndOptions then
		self.wndOptionsList:Destroy()
		self.wndOptionsList = nil
		self.wndOptions:Destroy()
		self.wndOptions = nil
	end
end

function TLoot:OnOptionsWindowMove(wndHandler, wndControl, nOldLeft, nOldTop, nOldRight, nOldBottom)
	local nScreenWidth, nScreenHeight = Apollo.GetScreenSize()
	local nPosLeft, nPosTop = self.wndOptions:GetPos()
	self.settings.tOptionsWindowPos[1], self.settings.tOptionsWindowPos[2] = nPosLeft / nScreenWidth, nPosTop / nScreenHeight
end

function TLoot:SetOptionValues()
	Logger:debug("SetOptionValues")
	
	self.wndOptionsList:FindChild("UpdateSpeed"):FindChild("Slider"):SetValue(self.settings.nBarUpdateSpeed)
	self.wndOptionsList:FindChild("UpdateSpeed"):FindChild("Value"):SetText(self.settings.nBarUpdateSpeed)
	self.wndOptionsList:FindChild("BarWidth"):FindChild("Slider"):SetValue(self.settings.nBarWidth)
	self.wndOptionsList:FindChild("BarWidth"):FindChild("Value"):SetText(self.settings.nBarWidth)
	self.wndOptionsList:FindChild("BarHeight"):FindChild("Slider"):SetValue(self.settings.nBarHeight)
	self.wndOptionsList:FindChild("BarHeight"):FindChild("Value"):SetText(self.settings.nBarHeight)
	
	self.wndOptionsList:FindChild("Direction"):FindChild("UpBtn"):SetCheck(not self.settings.bBottomToTop)
	self.wndOptionsList:FindChild("Direction"):FindChild("DownBtn"):SetCheck(self.settings.bBottomToTop)
	
	self.wndOptionsList:FindChild("NeedKeybind"):FindChild("InputBox"):SetText(ktKeys[self.settings.nNeedKeybind])
	self.wndOptionsList:FindChild("NeedKeybind"):FindChild("EnableBtn"):SetCheck(self.settings.bNeedKeybind)
	self.wndOptionsList:FindChild("GreedKeybind"):FindChild("InputBox"):SetText(ktKeys[self.settings.nGreedKeybind])
	self.wndOptionsList:FindChild("GreedKeybind"):FindChild("EnableBtn"):SetCheck(self.settings.bGreedKeybind)
	self.wndOptionsList:FindChild("PassKeybind"):FindChild("InputBox"):SetText(ktKeys[self.settings.nPassKeybind])
	self.wndOptionsList:FindChild("PassKeybind"):FindChild("EnableBtn"):SetCheck(self.settings.bPassKeybind)
end

function TLoot:OnBarUpdateSpeedSliderChanged(wndHandler, wndControl, fNewValue, fOldValue)
	if wndHandler ~= wndControl then
		return
	end
	
	self.settings.nBarUpdateSpeed = round(fNewValue, 1, true)
	wndControl:GetParent():GetParent():FindChild("Value"):SetText(self.settings.nBarUpdateSpeed)
	
	-- Update timer
	Apollo.CreateTimer("LootUpdateTimer", self.settings.nBarUpdateSpeed, false)
	if not self.bTimerRunning then
		Apollo.StopTimer("LootUpdateTimer")
	end
end

function TLoot:OnBarWidthSliderChanged(wndHandler, wndControl, fNewValue, fOldValue)
	if wndHandler ~= wndControl then
		return
	end
	
	self.settings.nBarWidth = round(fNewValue, 0, true)
	wndControl:GetParent():GetParent():FindChild("Value"):SetText(self.settings.nBarWidth)
	
	-- Update existing bars
	self:ResizeAllBars(self.settings.nBarWidth, self.settings.nBarHeight)
end

function TLoot:OnBarHeightSliderChanged(wndHandler, wndControl, fNewValue, fOldValue)
	if wndHandler ~= wndControl then
		return
	end
	
	self.settings.nBarHeight = round(fNewValue, 0, true)
	wndControl:GetParent():GetParent():FindChild("Value"):SetText(self.settings.nBarHeight)
	
	-- Update existing bars
	self:ResizeAllBars(self.settings.nBarWidth, self.settings.nBarHeight)
end

function TLoot:OnReloadBtn(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	RequestReloadUI()
end

function TLoot:OnResetBtn(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	self.settings = copyTable(ktDefaultSettings)
	RequestReloadUI()
end

function TLoot:OnNeedKeybindChanged(wndHandler, wndControl, sText)
	local sKey = string.upper(string.sub(sText, 1, 2))
	local nKey = getKey(ktKeys, sKey)
	
	if nKey ~= nil then
		self.settings.nNeedKeybind = nKey
	else
		sKey = ktKeys[self.settings.nNeedKeybind]
	end
	
	wndHandler:SetText(sKey)
	wndHandler:ClearFocus()
end

function TLoot:OnGreedKeybindChanged(wndHandler, wndControl, sText)
	local sKey = string.upper(string.sub(sText, 1, 2))
	local nKey = getKey(ktKeys, sKey)
	
	if nKey ~= nil then
		self.settings.nGreedKeybind = nKey
	else
		sKey = ktKeys[self.settings.nGreedKeybind]
	end
	
	wndHandler:SetText(sKey)
	wndHandler:ClearFocus()
end

function TLoot:OnPassKeybindChanged(wndHandler, wndControl, sText)
	local sKey = string.upper(string.sub(sText, 1, 2))
	local nKey = getKey(ktKeys, sKey)
	
	if nKey ~= nil then
		self.settings.nPassKeybind = nKey
	else
		sKey = ktKeys[self.settings.nPassKeybind]
	end
	
	wndHandler:SetText(sKey)
	wndHandler:ClearFocus()
end

function TLoot:OnNeedKeybindEnableBtn(wndHandler, wndControl)
	self.settings.bNeedKeybind = wndHandler:IsChecked()
end

function TLoot:OnGreedKeybindEnableBtn(wndHandler, wndControl)
	self.settings.bGreedKeybind = wndHandler:IsChecked()
end

function TLoot:OnPassKeybindEnableBtn(wndHandler, wndControl)
	self.settings.bPassKeybind = wndHandler:IsChecked()
end

-----------------------------------------------------------------------------------------------
-- Helper Functions
-----------------------------------------------------------------------------------------------
function copyTable(orig)
	local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[copyTable(orig_key)] = copyTable(orig_value)
        end
        setmetatable(copy, copyTable(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function mergeTables(t1, t2)
    for k, v in pairs(t2) do
    	if type(v) == "table" then
			if t1[k] then
	    		if type(t1[k] or false) == "table" then
	    			mergeTables(t1[k] or {}, t2[k] or {})
	    		else
	    			t1[k] = v
	    		end
			else
				t1[k] = {}
    			mergeTables(t1[k] or {}, t2[k] or {})
			end
    	else
    		t1[k] = v
    	end
    end
    return t1
end

function count(ht)
	if not ht then
		return 0
	end
	local count = 0
	for k, v in pairs(ht) do
		if v ~= nil then
			count = count + 1
		end
	end
	return count
end

function round(n, nDecimals, bForceDecimals)
	local nMult = 1
	if nDecimals and nDecimals > 0 then
		for i = 1, nDecimals do nMult = nMult * 10 end
	end
	n = math.floor((n * nMult) + 0.5) / nMult
	if bForceDecimals then n = string.format("%." .. nDecimals .. "f", n) end
	return n
end

function getKey(tTable, item)
	for key, value in pairs(tTable) do
		if value == item then
			return key
		end
	end
	return nil
end