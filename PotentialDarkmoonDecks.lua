local addonName, addon = ...
LibStub('AceAddon-3.0'):NewAddon(addon, addonName, 'AceConsole-3.0')
local AceGUI = LibStub("AceGUI-3.0")

addon:RegisterChatCommand("pdd", "pddCommand")
addon:RegisterChatCommand("pddgui", "pddguiCommand")

local function dumpTable(table, depth)
  if (depth > 200) then
    addon:Print("Error: Depth > 200 in dumpTable()")
    return
  end
  for k,v in pairs(table) do
    if (type(v) == "table") then
      addon:Print(string.rep("  ", depth)..k..":")
      dumpTable(v, depth+1)
    else
      addon:Print(string.rep("  ", depth)..k..": ",v)
    end
  end
end

local function contains(list, x)
	for _, v in pairs(list) do
		if v == x then return true end
	end
	return false
end

local validRanks = { 
   ["Ace"] = 1, 
   ["Two"] = 2, 
   ["Three"] = 3, 
   ["Four"] = 4,
   ["Five"] = 5,
   ["Six"] = 6,
   ["Seven"] = 7,
   ["Eight"] = 8,
   ["Blank Card"] = 9 -- special, same as Joker
}

-- TODO: match jokers ("{suit} Joker" and "Blank Card of {suit}")

local function isDMCard(itemLink)
   -- cards look like regex "[(Ace|Two|Three|Four|Five|Six|Seven|Eight|Blank Card) of (<deck name>]"
   if not itemLink then
      return false
   end
   local found, _, rank, suit = string.find(itemLink, "%[(%a+) of ([%a ]+)]")
   if not found then
      found, _, suit, rank = string.find(itemLink, "%[(%a+) (Joker)")
   end
   if not found then
      return false
   end
   if rank == "Joker" then
      rank = "Blank Card"
   end
   if not validRanks[rank] then
      return false
   end
   -- tell the server to send us the details. This happens asynchronously but we need it later
   GetItemInfo(itemLink)
   local cardInfo = { rank=rank, suit=suit, itemLink = itemLink }
   -- cache item details
   local item = Item:CreateFromItemLink(itemLink)
   item:ContinueOnItemLoad(function()
      cardInfo.itemLevel = item:GetCurrentItemLevel()
      -- addon:Print(itemLink .. " " .. tostring(cardInfo.itemLevel))
   end)
   return cardInfo
end

local function AddCard(cards, cardInfo, source)
   local suit = cardInfo.suit
   -- addon:Print("AddCard " .. cardInfo.rank .. " of " .. suit .. " from " .. source)
   if not cards[suit] then
      cards[suit] = {}
   end
   local rankNumber = validRanks[cardInfo.rank]
   if not cards[suit][rankNumber] then
      cards[suit][rankNumber] = cardInfo
   end
end

-- with TWW and the warbank, we can now look on "disconnected realms" and both factions
local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local searchAllRealms = isRetail

local function FindCards()
   local connectedRealms
   if not searchAllRealms then connectedRealms = GetAutoCompleteRealms() end
	local currentFaction = UnitFactionGroup("player")
   local guilds = {}
   local cards = {}
	for account in pairs(DataStore:GetAccounts()) do
		for realm in pairs(DataStore:GetRealms(account)) do
         if not connectedRealms or contains(connectedRealms, realm) then
            for characterName, character in pairs(DataStore:GetCharacters(realm, account)) do
               if searchAllRealms or (DataStore:GetCharacterFaction(character) == currentFaction) then
               local characterNameWithRealm = characterName .. "-" .. realm
                  -- check this character's inventory
                  -- addon:Print("checking inventory " .. characterNameWithRealm)
                  DataStore:IterateContainerSlots(character, function(containerName, itemID, itemLink, itemCount, isBattlePet)
                     local cardInfo = isDMCard(itemLink) 
                     if cardInfo then
                        AddCard(cards, cardInfo, characterNameWithRealm .. " inventory")
                     end
                  end)
                  -- check this character's guild bank
                  local guildName = DataStore:GetGuildName(character)
                  -- addon:Print(characterNameWithRealm .. "(" .. tostring(character) .. ") is in guild " .. tostring(guildName))
                  if guildName and not contains(guilds, guildName) then
                     -- addon:Print("checking guild vault " .. guildName .. " for " .. characterNameWithRealm)
                     -- local guild = GetCharacterGuild(account, realm, guildName)
                     -- if guild then
                     local guildID = DataStore:GetCharacterGuildID(character)
                     if guildID then
                        -- addon:Print("checking guild bank " .. guildName)
                        table.insert(guilds, guildName)
                        local guild = account .. "." .. realm .. "." .. guildName
                        DataStore:IterateGuildBankSlots(guild, function(location, itemID, itemLink, itemCount, isBattlePet)
                           local cardInfo = isDMCard(itemLink, true) 
                           if cardInfo then
                              AddCard(cards, cardInfo, "guild bank " .. guildName)
                           end
                        end)
                     end
                  end
               end
            end
         end
		end
   end
   return cards
end

-- our slash command /pdd

function addon:pddCommand(input)
   local cards = FindCards()
   -- todo: sort output, ideally by expansion, then suit
   for suit, ranks in pairs(cards) do
      local line = ""
      local missing = 8
      for rank = 1, 9 do
         local cardInfo = ranks[rank]
         local present = "*"
         if cardInfo then
            missing = missing - 1
         else
            present = " "
         end
         line = line .. " " .. present
      end
      line = line .. " " .. tostring(missing) .. " " .. suit
      addon:Print(line)
   end

end

local function AddCardIcon(parent, cardInfo)
         slot = AceGUI:Create("Icon")
         slot:SetWidth(74)
         slot:SetHeight(74)
         -- now that we know the size, add to the parent to do the layout,
         -- before setting the texture and arranging for a tooltip.
         parent:AddChild(slot)
         if cardInfo then
            slot:SetUserData("itemLink", cardInfo.itemLink)
            local itemID = tonumber(cardInfo.itemLink:match("item:(%d+)"))
            local item = Item:CreateFromItemLink(cardInfo.itemLink)
            -- callback will set texture when it arrives from server
            local _, _, _, _, icon, _, _ = GetItemInfoInstant(itemID) -- added in 7.0.3
            slot:SetImage(icon)
            item:ContinueOnItemLoad(function()
               local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
               if texture then
                  slot:SetImage(texture)
               else
                  addon:Print("ContinueOnItemLoad nil texture for " .. cardInfo.itemLink)
               end
            end)
            slot:SetCallback("OnEnter", function(slot)
               GameTooltip:SetOwner(slot.frame, "ANCHOR_CURSOR")
               local itemLink = slot:GetUserData("itemLink")
               GameTooltip:SetHyperlink(slot:GetUserData("itemLink"))
               GameTooltip:Show()
            end)
            slot:SetCallback("OnLeave", function()
               GameTooltip:Hide()
            end)
         else
            slot:SetDisabled(true)
         end
end

function addon:pddguiCommand(input)
   local f = AceGUI:Create("Window")
   f:SetCallback("OnClose",function(widget) AceGUI:Release(widget) end)
   f:SetTitle("Potential Darkmoon Decks")
   f:SetLayout("Fill")
   f:SetWidth((9 * 80) + 200)

   scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   f:AddChild(scroll)

   local cards = FindCards()

   -- add each suit as a SimpleGroup of 8 items and a Label for the suit name

   for suit, ranks in pairs(cards) do
      local group = AceGUI:Create("SimpleGroup")
      group:SetFullWidth(true)
      group:SetLayout("Flow")
      scroll:AddChild(group)
      for rank = 1, 9 do
         AddCardIcon(group, ranks[rank])
      end
      local label = AceGUI:Create("Label")
      label:SetFontObject(GameFontNormalLarge)
      label:SetText("  " .. suit)
      group:AddChild(label)
   end

end

function pddgui_OnAddonCompartmentClick(addonName, mouseButton, button)
   addon:pddguiCommand(nil)
end

local minimapButtonCreated = false

function addon:createMinimapButton()
   if minimapButtonCreated then return end
   local prettyName = "Potential Darkmoon Decks"
   local miniButton = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
      type = "data source",
      text = prettyName,
      icon = "Interface\\Icons\\inv_misc_ticket_tarot_stack_01",
      OnClick = function(self, btn)
         addon:pddguiCommand(nil)
      end,
      OnTooltipShow = function(tooltip)
         if not tooltip or not tooltip.AddLine then return end
         tooltip:AddLine(prettyName)
      end,
   })
   local icon = LibStub("LibDBIcon-1.0", true)
   icon:Register(addonName, miniButton)
   minimapButtonCreated = true
end

addon:createMinimapButton()
