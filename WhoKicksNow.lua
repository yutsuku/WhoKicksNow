local tinsert = tinsert
local getn = getn
local strupper = strupper
local ceil = ceil
local strfind = strfind
local gmatch = string.gfind
local GetTime = GetTime
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local UnitName = UnitName
local UnitClass = UnitClass
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local MAINBAR_WIDTH = 140
local MAINBAR_HEIGHT = 30
local BAR_WIDTH = 140
local BAR_HEIGHT = 20
local BAR_HEIGHT_MAIN = 30
local COOLDOWN_WIDTH = 200
local COOLDOWN_HEIGHT = 20
local ICONF_WIDTH = 40
local ICONF_HEIGHT = 20
local ICON_WIDTH = 20
local ICON_HEIGHT = 20

local debug_level = 0
local NETWORK = true
local PAUSE = false
local addon = CreateFrame('Frame')

addon:SetScript('OnEvent', function()
	this[event](this)
end)

addon.Network = {
	Cooldown = 'C',
}

local SKILLS = {
	{name='Kick', cooldown=10, texture=[[Interface\Icons\Ability_Kick]]},
	{name='Cheap Shot', useHook=true, cooldown=1, texture=[[Interface\Icons\Ability_CheapShot]]},
	{name='Kidney Shot', useHook=true, cooldown=20, texture=[[Interface\Icons\Ability_Rogue_KidneyShot]]},
	{name='Gouge', cooldown=10, texture=[[Interface\Icons\Ability_Gouge]]},
}

local SPELLBOOK = {}

--addon:RegisterEvent('ADDON_LOADED')
addon:RegisterEvent('PLAYER_LOGIN')
addon:RegisterEvent('PARTY_MEMBERS_CHANGED')
addon:RegisterEvent('RAID_ROSTER_UPDATE')

function addon:RegisterCombatEvents()
	addon:RegisterEvent('CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS')
	addon:RegisterEvent('CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF')
	addon:RegisterEvent('CHAT_MSG_SPELL_SELF_DAMAGE')
	addon:RegisterEvent('CHAT_MSG_SPELL_PARTY_DAMAGE')
	addon:RegisterEvent('CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE')
	if NETWORK then
		addon:RegisterEvent('CHAT_MSG_ADDON')
	end
	self.SpellWatcher:RegisterEvent('SPELLCAST_STOP')
	
	-- looks like CS needs a hook for spell cast function
	--addon:RegisterEvent('SPELLCAST_STOP')
	--addon:RegisterEvent('CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE')
	-- "Fire Roc is afflicted by Cheap Shot."
	
	--addon:RegisterEvent('CHAT_MSG_SPELL_SELF_DAMAGE')
	-- "Your Gouge crits Fire Roc for 124."
	
	-- looks like KS needs a hook for spell cast function
	--addon:RegisterEvent('SPELLCAST_STOP')
	--addon:RegisterEvent('CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE')
	-- "Blisterpaw Hyena is afflicted by Kidney Shot"
end

function addon:UnregisterCombatEvents()
	addon:UnregisterEvent('CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS')
	addon:UnregisterEvent('CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF')
	addon:UnregisterEvent('CHAT_MSG_SPELL_SELF_DAMAGE')
	addon:UnregisterEvent('CHAT_MSG_SPELL_PARTY_DAMAGE')
	addon:UnregisterEvent('CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE')
	if NETWORK then
		addon:UnregisterEvent('CHAT_MSG_ADDON')
	end
	self.SpellWatcher:UnregisterEvent('SPELLCAST_STOP')
end

function addon:GetSkillInfo(skill)
	if not skill then
		return
	end
	for i=1, getn(SKILLS) do
		if SKILLS[i].name == skill then
			return SKILLS[i]
		end
	end
end

function addon:IsInGroup(name)
	if not name then return end
	for i=1, getn(self.groupMembers) do
		if self.groupMembers[i].name == name then
			return self.groupMembers[i].class
		end
	end
end

function addon:print(message, level, headless)
	if not message or message == '' then return end
	if level then
		if level <= debug_level then
			if headless then
				ChatFrame1:AddMessage(message, 0.53, 0.69, 0.19)
			else
				ChatFrame1:AddMessage('[WKN]: ' .. message, 0.53, 0.69, 0.19)
			end
		end
	else
		if headless then
			ChatFrame1:AddMessage(message)
		else
			ChatFrame1:AddMessage('[WKN]: ' .. message, 1.0, 0.61, 0)
		end
	end
end

function addon:CHAT_MSG_ADDON()
	if arg1 ~= 'WhoKicksNow' then
		return
	end
	
	self:print(format('--RAW [%s] --\n%s\n--ENDRAW--', arg4, arg2), 2)
	
	local msg = {}
	local len = 0
	for w in gmatch(arg2, '[^;]+') do
		len = len + 1
		self:print(format('[%d] WORD "%s"', len, w), 3)
		tinsert(msg, w)
	end 
	
	if len == 4 and msg[3] == self.Network.Cooldown and arg4 ~= UnitName('player') then
		-- received cooldown message
		local skillInfo = self:GetSkillInfo(msg[4])
		if not skillInfo then
			return
		end
		
		local obj = {
			name = skillInfo.name,
			remaining = skillInfo.cooldown,
			miss = false,
			cooldown = skillInfo.cooldown,
			texture = skillInfo.texture
		}
		
		table.insert(self.main_frame.trackers[arg4].cooldowns.t, obj)
		self.main_frame.trackers[arg4].cooldowns:Show()
		self:print('[NET] Showing cooldowns for '..arg4..' due to '..skillInfo.name, 1)
	end
end

function addon:NetworkSendUpdate(message)
	if not NETWORK then return end
	
	local msg = ''
	msg = msg .. 'WhoKicksNow;'
	msg = msg .. self.version .. ';'
	msg = msg .. message .. ';'
	
	if GetNumRaidMembers() > 0 then
		SendAddonMessage('WhoKicksNow', msg, 'RAID')
	elseif GetNumPartyMembers() > 0 then
		SendAddonMessage('WhoKicksNow', msg, 'PARTY')
	end
end

-- important combat events
function addon:CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS() -- can occur OUTSIDE PARTY TOO
	-- "Roguea's Kick was dodged by Earthborer"
	local _,_, name, skill = strfind(arg1, '^(%a-)\'s (.-) %l.- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not name or not skillInfo or not self:IsInGroup(name) then
		return
	end
	
	local obj = {
		name = skillInfo.name,
		remaining = skillInfo.cooldown,
		miss = true,
		cooldown = skillInfo.cooldown,
		texture = skillInfo.texture
	}
	
	table.insert(self.main_frame.trackers[name].cooldowns.t, obj)
	self.main_frame.trackers[name].cooldowns:Show()
	self:print('[DAMAGESHIELDS_ON_OTHERS] Showing cooldowns for '..name..' due to missed '..skillInfo.name, 1)
end

function addon:CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF()
	-- "Your Kick was dodged by Earthborer"
	-- "Your Gouge failed. Magistrate Barthilas is immune."
	-- "Your Cheap Shot failed. Magistrate Barthilas is immune."
	local _,_, skill = strfind(arg1, '^Your (.-) %l.- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not skillInfo then
		return
	end
	
	local obj = {
		name = skillInfo.name,
		remaining = skillInfo.cooldown,
		miss = true,
		cooldown = skillInfo.cooldown,
		texture = skillInfo.texture
	}
	
	if self.SpellWatcher.spells[skill] then
		self.SpellWatcher.spells[skill].fail = true
	end
	table.insert(self.main_frame.trackers[UnitName('player')].cooldowns.t, obj)
	self.main_frame.trackers[UnitName('player')].cooldowns:Show()
	self:print('[DAMAGESHIELDS_ON_SELF] Showing cooldowns for you due to missed '..skill, 1)
end

function addon:CHAT_MSG_SPELL_SELF_DAMAGE()
	self:print('CHAT_MSG_SPELL_SELF_DAMAGE', 1)
	-- "Your Kick hits Earthborer for 8."
	local _,_, skill = strfind(arg1, '^Your (.-) .- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not skillInfo then
		return
	end
	
	local obj = {
		name = skillInfo.name,
		remaining = skillInfo.cooldown,
		miss = false,
		cooldown = skillInfo.cooldown,
		texture = skillInfo.texture
	}
	
	table.insert(self.main_frame.trackers[UnitName('player')].cooldowns.t, obj)
	self.main_frame.trackers[UnitName('player')].cooldowns:Show()
	self:print('[SELF_DAMAGE] Showing cooldowns for you due to '..skill, 1)
	--[[self.main_frame.trackers[UnitName('player')].cooldowns.t
	
	this.cooldowns.t = {
		{name='Kidney Shot', remaining=20, cooldown=20, texture=[[Interface\Icons\Ability_Rogue_KidneyShot]]},
		{name='Kick', remaining=10, miss=true, cooldown=10, texture=[[Interface\Icons\Ability_Kick]]},
	}
	this.cooldowns:Show()
	self:print('Test mode for '..this.text:GetText())]]
end

function addon:CHAT_MSG_SPELL_PARTY_DAMAGE()
	self:print('CHAT_MSG_SPELL_PARTY_DAMAGE', 1)
	-- "Roguea's Kick hits Earthborer for 4. (7 blocked)"
	local _,_, name, skill = strfind(arg1, '^(.-)\'s (.-) .- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not skillInfo then
		return
	end
	
	local obj = {
		name = skillInfo.name,
		remaining = skillInfo.cooldown,
		miss = false,
		cooldown = skillInfo.cooldown,
		texture = skillInfo.texture
	}
	
	table.insert(self.main_frame.trackers[name].cooldowns.t, obj)
	self.main_frame.trackers[name].cooldowns:Show()
	self:print('[PARTY_DAMAGE] Showing cooldowns for '..name..' due to '..skillInfo.name, 1)
end

function addon:CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE() -- fucking raid groups, can occur OUTSIDE PARTY/RAID TOO
	local _,_, name, skill = strfind(arg1, '^(%a-)\'s (.-) %l.- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not name or not skillInfo or not self:IsInGroup(name) then
		return
	end
	
	local obj = {
		name = skillInfo.name,
		remaining = skillInfo.cooldown,
		miss = false,
		cooldown = skillInfo.cooldown,
		texture = skillInfo.texture
	}
	
	table.insert(self.main_frame.trackers[name].cooldowns.t, obj)
	self.main_frame.trackers[name].cooldowns:Show()
	self:print('[FRIENDLYPLAYER_DAMAGE] Showing cooldowns for '..name..' due to '..skillInfo.name, 1)
end
-- end of important combat events

function addon:ADDON_LOADED()
	if arg1 ~= 'WhoKicksNow' then
		return
	end
end

function addon:RAID_ROSTER_UPDATE()
	self:print('RAID_ROSTER_UPDATE', 1)
	self:HandlePlayerChange()
end

function addon:PARTY_MEMBERS_CHANGED()
	self:print('PARTY_MEMBERS_CHANGED', 1)
	self:HandlePlayerChange()
end

function addon:PLAYER_LOGIN()

	--[[local i = 1
	while true do
	local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
	if not spellName then
		do break end
	end

	-- use spellName and spellRank here
	DEFAULT_CHAT_FRAME:AddMessage( spellName .. '(' .. spellRank .. ')' )

	i = i + 1
	end]]
	
	if debug_level > 0 then
		WKN = self
	end
	self.groupMembers = {}
	self.enabled = true
	self.inGroup = false
	self.version = GetAddOnMetadata('WhoKicksNow', 'Version')
	
	--[[addon:RegisterAllEvents()
	addon:SetScript('OnEvent', function()
		local s = ""
		if arg1 then s = s..' arg1: '..arg1 end
		if arg2 then s = s..' arg2: '..arg2 end
		if arg3 then s = s..' arg3: '..arg3 end
		if arg4 then s = s..' arg4: '..arg4 end
		if arg5 then s = s..' arg5: '..arg5 end
		if arg6 then s = s..' arg6: '..arg6 end
		if arg7 then s = s..' arg7: '..arg7 end
		if arg8 then s = s..' arg8: '..arg8 end
		if arg9 then s = s..' arg9: '..arg9 end
		if ( strsub(event, 1, 8) == "CHAT_MSG" ) then
			self:print(event, 0)
			self:print(s, 0, true)
		else
			self:print(event, 1)
			self:print(s, 1, true)
		end
	end)]]
	
	-- relay on timing 
	local SPELL_FAIL_TIME = 0.3
	self.SpellWatcher = CreateFrame('Frame')
	self.SpellWatcher:SetScript('OnUpdate', function()
		local now = GetTime()
		for skill, spellData in pairs(self.SpellWatcher.spells) do
			if spellData.t+SPELL_FAIL_TIME < now then
				if spellData.fail or not spellData.cast then
					-- cast failed
					self.SpellWatcher.spells[skill] = nil
					self:print('[SpellWatcher] '..skill..' failed ('..spellData.t..', now: '..now..')', 1)
					break
				end
				
				-- cast was successful
				local skillInfo = self:GetSkillInfo(skill)
				if not skillInfo or not skillInfo.useHook then
					return
				end
				
				local obj = {
					name = skillInfo.name,
					remaining = skillInfo.cooldown,
					miss = false,
					cooldown = skillInfo.cooldown,
					texture = skillInfo.texture
				}
				
				table.insert(self.main_frame.trackers[UnitName('player')].cooldowns.t, obj)
				self.main_frame.trackers[UnitName('player')].cooldowns:Show()
				self:NetworkSendUpdate(format('%s;%s', self.Network.Cooldown, skillInfo.name))
				self:print('[SpellWatcher] Showing cooldowns for you due to '..skill..' ('..spellData.t+SPELL_FAIL_TIME..' < '..now..')', 1)
				self.SpellWatcher.spells[skill] = nil
			end
		end
		
	end)
	
	self.SpellWatcher:SetScript('OnEvent', function()
		local now = GetTime()
		if event == 'SPELLCAST_STOP' then
		
			for skill, spellData in pairs(self.SpellWatcher.spells) do
				self.SpellWatcher.spells[skill].cast = true
			end
			
		end
	end)
	
	--self.SpellWatcher:RegisterEvent('SPELLCAST_STOP')
	self.SpellWatcher.spells = {}
	
	-- hooks
	self.CastSpellByName = CastSpellByName
	--self.CastSpell = CastSpell
	self.UseAction = UseAction
	
	function CastSpellByName(msg)
		local skillInfo = self:GetSkillInfo(msg)
		--self:print('spellName: '..spellName..', slot: '..slot..', flags: '..flags..', onSelf: '..tostring(onSelf))
		if skillInfo and skillInfo.useHook then
			self:print('[SpellWatcher|ByName] updating '..msg, 1)
			self.SpellWatcher.spells[msg] = { t = GetTime() }
		end
		self.CastSpellByName(msg)
	end
	
	--[[function CastSpell(id, bookType)
		self:print(id..', type: '..bookType)
		self.CastSpell(id, bookType)
	end]] -- people dont clikc skills from book, right? RIGHT!?
	
	self.UseActionTooltip = CreateFrame('GameTooltip', 'WKNTooltip', UIParent, 'GameTooltipTemplate')
	self.UseActionTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	self.UseActionTooltipText = WKNTooltipTextLeft1
	
	function UseAction(slot, flags, onSelf)
		if IsUsableAction(slot) and GetActionCooldown(slot) == 0 then
			self.UseActionTooltip:ClearLines()
			self.UseActionTooltip:SetAction(slot)
			local spellName = self.UseActionTooltipText:GetText()
			local skillInfo = self:GetSkillInfo(spellName)
			--self:print('spellName: '..spellName..', slot: '..slot..', flags: '..flags..', onSelf: '..tostring(onSelf))
			if skillInfo and skillInfo.useHook then
				self:print('[SpellWatcher|Slot] updating '..spellName, 1)
				self.SpellWatcher.spells[spellName] = { t = GetTime() }
			end
		end
		self.UseAction(slot, flags, onSelf)
	end
	-- hooks end
	
	SLASH_WHOKICKSNOW1, SLASH_WHOKICKSNOW2, SLASH_WHOKICKSNOW3 = '/whokicksnow', '/whokicks', '/wk'
	function SlashCmdList.WHOKICKSNOW(arg)
		local msg = {}
		for w in gmatch(arg, '[^%s]+') do
			tinsert(msg, w)
		end
		
		if arg == 'debug' then
			debug_level = debug_level + 1
			if debug_level > 3 then debug_level = 0 end
			self:print('Debug level is now set to ' .. debug_level)
		elseif arg == 'pause' then
			if PAUSE then
				PAUSE = false
				self:print('Resuming timers')
			else
				PAUSE = true
				WKN_D1 = self.SpellWatcher.spells
				WKN_D2 = self.main_frame.trackers[UnitName('player')].cooldowns.t
				self:print('Pausing timers')
			end
		elseif arg == 'indexes' then
			for k,frame in pairs(self.main_frame.trackers) do
				if frame:IsVisible() then
					local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
					self:print(format('[%d] %s offset %d', frame.sortIndex, frame.text:GetText(), yOfs))
				end
			end
		else
			self:print('someday i will add useful message here')
		end
	end
	
	local main_frame = CreateFrame('Frame', nil, UIParent)
	self.main_frame = main_frame
	main_frame:SetPoint('CENTER', 0, 0)
	main_frame:SetWidth(MAINBAR_WIDTH)
	main_frame:SetHeight(MAINBAR_HEIGHT)
	main_frame:SetBackdrop({
		bgFile=[[Interface\Minimap\TooltipBackdrop-Background]],
		edgeFile=[[Interface\Minimap\TooltipBackdrop]],
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
    main_frame:SetBackdropColor(0, 0, 0, .6)
	main_frame:SetMovable(true)
	main_frame:SetClampedToScreen(true)
	main_frame:SetToplevel(true)
	main_frame:EnableMouse(true)
	main_frame:RegisterForDrag('LeftButton')
	main_frame:SetScript('OnDragStart', function()
		this:StartMoving()
	end)
	main_frame:SetScript('OnDragStop', function()
		this:StopMovingOrSizing()
	end)
	main_frame.trackers = {}
	main_frame.trackersCount = 0
	
	local text = main_frame:CreateFontString()
	main_frame.text = text
	text:SetFontObject(GameFontNormal)
	text:SetAllPoints()
	text:SetText('Who Kicks Now?')
end

local frameid = 1
function addon:CreateTracker(name, class)
	self:print('creating frame for '..name..', '..class, 1)

	if self.main_frame.trackers[name] then
		return self.main_frame.trackers[name]
	end
	
	local track_frame = CreateFrame('Frame', nil, self.main_frame)
	self.main_frame.trackers[name] = track_frame
	track_frame.id = frameid
	frameid = frameid + 1
	track_frame:SetPoint('TOP', 0, -(BAR_HEIGHT*self.main_frame.trackersCount))
	track_frame:SetWidth(BAR_WIDTH)
	track_frame:SetHeight(BAR_HEIGHT)
	track_frame:SetBackdrop({
		bgFile=[[Interface\Tooltips\ChatBubble-Background]],
		edgeFile=[[Interface\Tooltips\UI-Tooltip-Border]],
		tile = true,
		tileSize = 16,
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	--track_frame:SetBackdropColor(0, 0, 0, .6)
	track_frame:EnableMouse(true)
	track_frame:SetScript('OnMouseDown', function()
		if arg1 == 'RightButton' then
			this.cooldowns.t = {
				{name='Kidney Shot', remaining=20, cooldown=20, texture=[[Interface\Icons\Ability_Rogue_KidneyShot]]},
				{name='Kick', remaining=10, miss=true, cooldown=10, texture=[[Interface\Icons\Ability_Kick]]},
			}
			this.cooldowns:Show()
			self:print('Test mode for '..this.text:GetText())
		end
	end)
	
	local text = track_frame:CreateFontString()
	track_frame.text = text
	text:SetFontObject(GameFontNormal)
	text:SetTextColor(RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b)
	text:SetAllPoints()
	text:SetText(name)
	
	local button_up = CreateFrame('Button', nil, track_frame)
	track_frame.button_up = button_up
	button_up:SetPoint('RIGHT', self.main_frame.trackers[name], 'LEFT', 0, 0)
	button_up:SetWidth(ICON_WIDTH)
	button_up:SetHeight(ICON_HEIGHT)
	
	button_up:SetNormalTexture([[Interface\Buttons\UI-ScrollBar-ScrollUpButton-Up]])
	button_up:SetHighlightTexture([[Interface\Buttons\UI-ScrollBar-ScrollUpButton-Highlight]])
	button_up:SetDisabledTexture([[Interface\Buttons\UI-ScrollBar-ScrollUpButton-Disabled]])
	button_up:SetPushedTexture([[Interface\Buttons\UI-ScrollBar-ScrollUpButton-Down]])
	
	button_up:SetScript('OnClick', function()
		local id = this:GetParent().sortIndex
		local id_previous = id-1
		local id_next = id+1
		
		local tracker_current, tracker_previous, tracker_next
		
		self:print('[Up] '..id..' => '..id_previous, 1)
		
		for name, tracker in pairs(self.main_frame.trackers) do
			if tracker.sortIndex == id_next then
				tracker_next = tracker
			end
			if tracker.sortIndex == id_previous then
				tracker_previous = tracker
			end
			if tracker.sortIndex == id then
				tracker_current = tracker
			end
		end
		
		if tracker_previous and tracker_current then
			tracker_previous.sortIndex = id
			tracker_current.sortIndex = id_previous
			
			tracker_previous.button_up:Enable()
			tracker_previous.button_down:Enable()
			tracker_current.button_up:Enable()
			tracker_current.button_down:Enable()
			
			if tracker_current.sortIndex == 1 then
				tracker_current.button_up:Disable()
			end
			
			if tracker_previous.sortIndex == self.main_frame.trackersCount then
				tracker_previous.button_down:Disable()
			end
			
			tracker_current:SetPoint('TOP', 0, -MAINBAR_HEIGHT-((tracker_current.sortIndex-1)*BAR_HEIGHT))
			tracker_previous:SetPoint('TOP', 0, -MAINBAR_HEIGHT-((tracker_previous.sortIndex-1)*BAR_HEIGHT))
		end
		
	end)
	
	local button_down = CreateFrame('Button', nil, track_frame)
	track_frame.button_down = button_down
	button_down:SetPoint('RIGHT', self.main_frame.trackers[name], 'LEFT', -ICON_WIDTH, 0)
	button_down:SetWidth(ICON_WIDTH)
	button_down:SetHeight(ICON_HEIGHT)
	
	button_down:SetNormalTexture([[Interface\Buttons\UI-ScrollBar-ScrollDownButton-Up]])
	button_down:SetHighlightTexture([[Interface\Buttons\UI-ScrollBar-ScrollDownButton-Highlight]])
	button_down:SetDisabledTexture([[Interface\Buttons\UI-ScrollBar-ScrollDownButton-Disabled]])
	button_down:SetPushedTexture([[Interface\Buttons\UI-ScrollBar-ScrollDownButton-Down]])
	
	button_down:SetScript('OnClick', function()
		local id = this:GetParent().sortIndex
		local id_previous = id-1
		local id_next = id+1
		
		local tracker_current, tracker_previous, tracker_next
		
		self:print('[Down] '..id..' => '..id_next, 1)
		
		for name, tracker in pairs(self.main_frame.trackers) do
			if tracker.sortIndex == id_next then
				tracker_next = tracker
			end
			if tracker.sortIndex == id_previous then
				tracker_previous = tracker
			end
			if tracker.sortIndex == id then
				tracker_current = tracker
			end
		end
		
		if tracker_next and tracker_current then
			tracker_next.sortIndex = id
			tracker_current.sortIndex = id_next
			
			tracker_next.button_up:Enable()
			tracker_next.button_down:Enable()
			tracker_current.button_up:Enable()
			tracker_current.button_down:Enable()
			
			if tracker_current.sortIndex == self.main_frame.trackersCount then
				tracker_current.button_down:Disable()
			end
			
			if tracker_next.sortIndex == 1 then
				tracker_next.button_up:Disable()
			end
			
			tracker_next:SetPoint('TOP', 0, -MAINBAR_HEIGHT-((tracker_next.sortIndex-1)*BAR_HEIGHT))
			tracker_current:SetPoint('TOP', 0, -MAINBAR_HEIGHT-((tracker_current.sortIndex-1)*BAR_HEIGHT))
		end
		
	end)
	
	local cooldowns = self.main_frame.trackers[name].cooldowns or CreateFrame('Frame', nil, self.main_frame.trackers[name])
	self.main_frame.trackers[name].cooldowns = cooldowns
	cooldowns:SetPoint('LEFT', self.main_frame.trackers[name], 'RIGHT', 0, 0)
	cooldowns:SetWidth(COOLDOWN_WIDTH)
	cooldowns:SetHeight(COOLDOWN_HEIGHT)
	cooldowns:SetBackdrop({
		bgFile=[[Interface\ChatFrame\ChatFrameBackground]],
		tile = true,
		tileSize = 16,
	})
    cooldowns:SetBackdropColor(0, 0, 0, .6)
	
	cooldowns.icons = {}
	cooldowns.MakeIcon = function(obj, parent)
		local iconFrame = CreateFrame('Frame', nil, parent)
		this.icons[obj.name] = iconFrame
		iconFrame:SetWidth(ICONF_WIDTH)
		iconFrame:SetHeight(ICONF_HEIGHT)
		iconFrame.unused = false
		
		local icon = iconFrame:CreateTexture()
		iconFrame.icon = icon
		icon:SetPoint('TOPLEFT', iconFrame, 'TOPLEFT', 0, 0)
		icon:SetWidth(ICON_WIDTH)
		icon:SetHeight(ICON_HEIGHT)
		icon:SetTexture(obj.texture)
		
		local text = iconFrame:CreateFontString()
		iconFrame.text = text
		text:SetFontObject(GameFontNormal)
		text:SetJustifyH('LEFT')
		--text:SetAllPoints(icon)
		text:SetPoint('LEFT', icon, 'RIGHT', 1, 0)
		
		return iconFrame
	end
	
	cooldowns.t = {}
	--[[
		{
			{name='Kick', remaining=2, miss=false, cooldown=10, texture=[[Interface\Icons\Ability_Kick]]},
		}
	]]
	cooldowns:SetScript('OnUpdate', function()
		if PAUSE then return end
		-- update timers
		for i=getn(this.t), 1, -1 do
			this.t[i].remaining = this.t[i].remaining-arg1
			if this.t[i].remaining <= 0 then
				this.icons[this.t[i].name]:Hide()
				tremove(this.t, i)
			end
		end
		
		if getn(this.t) == 0 then this:Hide() return end
		
		this:SetWidth(getn(this.t) * ICONF_WIDTH)
		
		local iconFrame
		for i=1, getn(this.t) do
			iconFrame = this.icons[this.t[i].name] or this.MakeIcon(this.t[i], this)
			if i == 1 then
				iconFrame:SetPoint('LEFT', this, 'LEFT', 0, 0)
			else
				iconFrame:SetPoint('LEFT', this, 'LEFT', ICONF_WIDTH*(i-1), 0)
			end
			iconFrame.text:SetText(ceil(this.t[i].remaining))
			if this.t[i].miss then
				iconFrame.icon:SetVertexColor(1, 0, 0)
			else
				iconFrame.icon:SetVertexColor(1, 1, 1)
			end
			iconFrame:Show()
		end
	end)
	
	return track_frame
	--track_frame:Show()
end

function addon:HandlePlayerChange()
	local players = {}
	if GetNumRaidMembers() > 0 then
		local name, _, class
		for i=1, GetNumRaidMembers() do
			_, class = UnitClass('raid'..i)
			name = UnitName('raid'..i)
			if name and class then
				players[i] = {name=name,class=strupper(class)}
			end
		end
		self.inGroup = true
	elseif GetNumPartyMembers() > 0 then
		local name, _, class
		for i=1, GetNumPartyMembers() do
			_, class = UnitClass('party'..i)
			name = UnitName('party'..i)
			if name and class then
				players[i] = {name=name,class=strupper(class)}
			end
		end
		_, class = UnitClass('player')
		players[GetNumPartyMembers()+1] = {name=UnitName('player'),class=strupper(class)}
		self.inGroup = true
	else
		self.inGroup = false
	end
	self.groupMembers = players
	
	for k,frame in pairs(self.main_frame.trackers) do
		-- reset sort index from non-group players
		if not self:IsInGroup(frame.text:GetText()) then
			frame.sortIndex = nil
		end
		frame:Hide()
	end
	self.main_frame.trackersCount = 0
	
	if self.inGroup then
		local track_frame
		local unsorted = {}
		
		for i=1, getn(self.groupMembers) do
			if self.groupMembers[i].class == 'ROGUE' then
				self.main_frame.trackersCount = self.main_frame.trackersCount + 1
				track_frame = self:CreateTracker(self.groupMembers[i].name, self.groupMembers[i].class)
				--[[if i == 1 then
					track_frame:SetPoint('TOP', 0, -MAINBAR_HEIGHT)
				else
					track_frame:SetPoint('TOP', 0, -MAINBAR_HEIGHT-((self.main_frame.trackersCount-1)*BAR_HEIGHT))
				end]]
				unsorted[self.main_frame.trackersCount] = track_frame
				--track_frame:Show()
			end
		end
		
		sort(unsorted, function(a, b)
			-- sort by index pairs, then index if any, then name
			if a.sortIndex and b.sortIndex then
				return a.sortIndex < b.sortIndex
			end
			if a.sortIndex and not b.sortIndex then
				return true
			end
			if b.sortIndex and not a.sortIndex then
				return false
			end

			return a.text:GetText() < b.text:GetText()
		end)
		
		self:print('adjusting frames position', 1)
		for i=1, self.main_frame.trackersCount do
			unsorted[i].button_up:Enable()
			unsorted[i].button_down:Enable()
			if i == 1 then
				self:print(format('[%d] %s is first', unsorted[i].sortIndex or -1, unsorted[i].text:GetText()), 1)
				unsorted[i]:SetPoint('TOP', 0, -MAINBAR_HEIGHT)
				unsorted[i].button_up:Disable()
			elseif i == self.main_frame.trackersCount then
				self:print(format('[%d] %s is last (of %d)', unsorted[i].sortIndex or -1, unsorted[i].text:GetText(), self.main_frame.trackersCount), 1)
				unsorted[i]:SetPoint('TOP', 0, -MAINBAR_HEIGHT-((self.main_frame.trackersCount-1)*BAR_HEIGHT))
				unsorted[i].button_down:Disable()
			elseif self.main_frame.trackersCount == 1 then
				self:print(format('[%d] %s is alone', unsorted[i].sortIndex or -1, unsorted[i].text:GetText()), 1)
				unsorted[i]:SetPoint('TOP', 0, -MAINBAR_HEIGHT)
				unsorted[i].button_up:Disable()
				unsorted[i].button_down:Disable()
			else
				self:print(format('[%d] %s', unsorted[i].sortIndex or -1, unsorted[i].text:GetText()), 1)
				unsorted[i]:SetPoint('TOP', 0, -MAINBAR_HEIGHT-((i-1)*BAR_HEIGHT))
			end
			unsorted[i].sortIndex = i
			unsorted[i]:Show()
			self:print(format('Showing frame for [%d] %s', unsorted[i].sortIndex, unsorted[i].text:GetText()), 1)
		end
		
		self:RegisterCombatEvents()
	else
		self:UnregisterCombatEvents()
	end
end