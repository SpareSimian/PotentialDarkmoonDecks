local addonName, addon = ...
LibStub('AceAddon-3.0'):NewAddon(addon, addonName, 'AceConsole-3.0')
local AceGUI = LibStub("AceGUI-3.0")

addon:RegisterChatCommand("pdd", "pddCommand")
addon:RegisterChatCommand("pddgui", "pddguiCommand")

local function dumpTable(table, depth)
  if (depth > 200) then
    print("Error: Depth > 200 in dumpTable()")
    return
  end
  for k,v in pairs(table) do
    if (type(v) == "table") then
      print(string.rep("  ", depth)..k..":")
      dumpTable(v, depth+1)
    else
      print(string.rep("  ", depth)..k..": ",v)
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
   ["Eight"] = 8 
}

local function isDMCard(itemLink)
   -- cards look like regex "[(Ace|Two|Three|Four|Five|Six|Seven|Eight) of (<deck name>]"
   local found, _, rank, suit = string.find(itemLink, "%[(%a+) of ([%a ]+)]")
   if not found then
      return false
   end
   if not validRanks[rank] then
      return false
   end
   local cardInfo = { rank=rank, suit=suit, itemLink = itemLink }
   -- cache item details
   local item = Item:CreateFromItemLink(itemLink)
   item:ContinueOnItemLoad(function()
      cardInfo.itemLevel = item:GetCurrentItemLevel()
      -- print(itemLink .. " " .. tostring(cardInfo.itemLevel))
   end)
   return cardInfo
end

local function GetCharacterGuild(account, realm, guildName)
   local guildKey = DataStore:GetGuild(guildName, realm, account)
   if guildKey then
      return DataStore_Containers.db.global.Guilds[guildKey]
   end
end

local function _IterateGuildBankSlots(guild, callback)
	for tabID, tab in pairs(guild.Tabs) do
		if tab.name then
			for slotID = 1, 98 do
				local itemID, itemLink, itemCount, isBattlePet = DataStore:GetSlotInfo(tab, slotID)
				
				-- Callback only if there is an item in that slot
				if itemID then
					local location = format("%s, %s - col %d/row %d)", GUILD_BANK, tab.name, floor((slotID-1)/7)+1, ((slotID-1)%7)+1)
				
					callback(location, itemID, itemLink, itemCount, isBattlePet)
				end
			end
		end
	end
end

local function AddCard(cards, cardInfo)
   local suit = cardInfo.suit
   -- addon:Print("AddCard " .. cardInfo.rank .. " of " .. suit)
   if not cards[suit] then
      cards[suit] = {}
   end
   local rankNumber = validRanks[cardInfo.rank]
   if not cards[suit][rankNumber] then
      cards[suit][rankNumber] = cardInfo
   end
end

local function FindCards()
   local connectedRealms = GetAutoCompleteRealms()
	local currentFaction = UnitFactionGroup("player")
   local guilds = {}
   local cards = {}
	for account in pairs(DataStore:GetAccounts()) do
		for realm in pairs(DataStore:GetRealms(account)) do
         if contains(connectedRealms, realm) then
            for characterName, character in pairs(DataStore:GetCharacters(realm, account)) do
               if DataStore:GetCharacterFaction(character) == currentFaction then
                  -- check this character's inventory
                  DataStore:IterateContainerSlots(character, function(containerName, itemID, itemLink, itemCount, isBattlePet)
                     local cardInfo = isDMCard(itemLink) 
                     if cardInfo then
                        AddCard(cards, cardInfo)
                        -- addon:Print(characterName .. " has card " .. itemLink)
                     end
                  end)
                  -- check this character's guild bank
                  local guildName = DataStore:GetGuildInfo(character)
                  if guildName and not contains(guilds, guildName) then
                     local guild = GetCharacterGuild(account, realm, guildName)
                     if guild then
                        -- addon:Print("checking guild bank " .. guildName)
                        table.insert(guilds, guildName)
                        _IterateGuildBankSlots(guild, function(location, itemID, itemLink, itemCount, isBattlePet)
                           local cardInfo = isDMCard(itemLink) 
                           if cardInfo then
                              AddCard(cards, cardInfo)
                              -- addon:Print(guildName .. " has card " .. itemLink)
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
      for rank = 1, 8 do
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

function addon:pddguiCommand(input)
   local f = AceGUI:Create("Frame")
   f:SetCallback("OnClose",function(widget) AceGUI:Release(widget) end)
   f:SetTitle("Potential Darkmoon Decks")
   f:SetLayout("Fill")

   scroll = AceGUI:Create("ScrollFrame")
   scroll:SetLayout("List")
   f:AddChild(scroll)

   local cards = FindCards()

   -- add each suit as a SimpleGroup of 8 items and a Label for the suit name

   for suit, ranks in pairs(cards) do
      local group = AceGUI:Create("InlineGroup")
      group:SetLayout("Flow")
      for rank = 1, 8 do
         local cardInfo = ranks[rank]
         slot = AceGUI:Create("ActionSlotItem")
         if cardInfo then
            slot:SetText(cardInfo.itemLink)
         else
            slot:SetDisabled(true)
         end
         group:AddChild(slot)
      end
      local label = AceGUI:Create("Label")
      label:SetText(suit)
      group:AddChild(label)
      scroll:AddChild(group)
   end

end
