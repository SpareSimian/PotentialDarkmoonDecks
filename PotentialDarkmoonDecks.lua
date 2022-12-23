

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
   local pos, last, rank, suit = string.find(itemLink, "%[(%a+) of ([%a ]+)]")
   if not pos then
      return pos
   end
   if not validRanks[rank] then
      return false
   end
   return pos, last, rank, suit
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

local function AddCard(cards, rank, suit)
   -- print("AddCard " .. rank .. " of " .. suit)
   if not cards[suit] then
      cards[suit] = {}
   end
   local rankNumber = validRanks[rank]
   if not cards[suit][rankNumber] then
      cards[suit][rankNumber] = 1
   else
      cards[suit][rankNumber] = cards[suit][rankNumber] + 1
   end
end

SLASH_PDD1="/pdd"
SlashCmdList["PDD"] = function(msg)
   print("Potential Darkmoon decks:")
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
                     local pos, last, rank, suit = isDMCard(itemLink) 
                     if pos then
                        AddCard(cards, rank, suit)
                        --print("PDD: " .. characterName .. " has card " .. itemLink)
                     end
                  end)
                  -- check this character's guild bank
                  local guildName = DataStore:GetGuildInfo(character)
                  if guildName and not contains(guilds, guildName) then
                     local guild = GetCharacterGuild(account, realm, guildName)
                     if guild then
                        -- print("PDD: checking guild bank " .. guildName)
                        table.insert(guilds, guildName)
                        _IterateGuildBankSlots(guild, function(location, itemID, itemLink, itemCount, isBattlePet)
                           local pos, last, rank, suit = isDMCard(itemLink) 
                           if pos then
                              AddCard(cards, rank, suit)
                              -- print("PDD: " .. guildName .. " has card " .. itemLink)
                           end
                        end)
                     end
                  end
               end
            end
         end
		end
   end
   table.sort(cards)
   for suit, ranks in pairs(cards) do
      local line = ""
      local missing = 8
      for rank = 1, 10 do
         local count = ranks[rank]
         if count then
            missing = missing - 1
         else
            count = 0 
         end
         line = line .. " " .. tostring(count)
      end
      line = line .. " " .. tostring(missing) .. " " .. suit
      print(line)
   end
end
