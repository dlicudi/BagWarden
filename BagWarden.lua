local itemTexts = {}
local itemSets
local MIN_FRAME_WIDTH = 200
local MIN_FRAME_HEIGHT = 300


BagWardenFrame = CreateFrame("Frame", "BagWardenFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
FrameTitle = BagWardenFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
FrameTitle:SetPoint("TOP", BagWardenFrame, "TOP", 0, -10)
FrameTitle:SetTextColor(1, 1, 0)  -- Yellow color

local currentSetLabel = BagWardenFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
currentSetLabel:SetPoint("TOPLEFT", 5, -5)


BagWardenFrame:SetSize(200, 200)
BagWardenFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = nil,
    tile = true,
    tileSize = 32,
    edgeSize = 12,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
BagWardenFrame:SetPoint("CENTER")
BagWardenFrame:EnableMouse(true)
BagWardenFrame:SetMovable(true)
BagWardenFrame:RegisterForDrag("LeftButton")
BagWardenFrame:SetScript("OnDragStart", BagWardenFrame.StartMoving)
BagWardenFrame:SetScript("OnDragStop", BagWardenFrame.StopMovingOrSizing)
BagWardenFrame:SetScript("OnHide", BagWardenFrame.StopMovingOrSizing)


local function GetItemLinkFromName(itemName)
    local itemID = select(1, GetItemInfoInstant(itemName))
    if itemID then
        return select(2, GetItemInfo(itemID))
    end
    return nil
end

local function CheckItems()
    local maxWidth = 0

    if not BagWardenData then
        BagWardenData = DeepCopy(DefaultData)
    end

    local set = BagWardenData.itemSets[BagWardenData.currentSet]
    FrameTitle:SetText(BagWardenData.currentSet)

    -- Update each item
    for i, item in ipairs(set) do
        local itemName, minCount = item.name, item.minCount
        local itemLink = GetItemLinkFromName(itemName) -- Get the item link
        local count = GetItemCount(itemName)
        local itemText = itemTexts[i]
        
        if not itemText then
            -- Create new font string for this item
            itemText = BagWardenFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            itemText:SetText(itemName)
            itemText:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 15 - 30) 
            itemTexts[i] = itemText
        end

        -- Attach tooltip to the itemText
        itemText:SetScript("OnEnter", function(self)
            if itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(itemLink)
                GameTooltip:Show()
            end
        end)
    
        itemText:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- itemText:SetUserPlaced(true)
        itemText:EnableMouse(true) -- Enable mouse events for the font string

        itemText:SetTextColor(count >= minCount and 0 or 1, count >= minCount and 1 or 0, 0)
        itemText:SetText(itemName .. ": " .. count .. "/" .. minCount)
        itemText:Show()

        -- Calculate max width
        local itemTextWidth = itemText:GetStringWidth()
        if itemTextWidth > maxWidth then
            maxWidth = itemTextWidth
        end
    end

    -- Resize the frame based on the number of items
    local numItems = #set
    local frameHeight = numItems * 15 + 40 
    BagWardenFrame:SetHeight(max(frameHeight, MIN_FRAME_HEIGHT))
    BagWardenFrame:SetWidth(max(maxWidth + 25, MIN_FRAME_WIDTH))
end


BagWardenFrame:RegisterEvent("BAG_UPDATE")
BagWardenFrame:SetScript("OnEvent", CheckItems)
BagWardenFrame:RegisterEvent("ADDON_LOADED")
BagWardenFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "BagWarden" then
        if not BagWardenData then
            BagWardenData = DeepCopy(DefaultData)
        end

        CheckItems()

        BagWardenFrame:UnregisterEvent("ADDON_LOADED")
    end

    if event == "BAG_UPDATE" and not InCombatLockdown() then
        CheckItems()
    end 
end)


SLASH_BagWarden1 = "/bw"
SlashCmdList["BagWarden"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")

    if cmd == "add" then
        local item_name, min_count = rest:match("(.*)%s(%d+)$")
        if item_name then item_name = item_name:match("^%s*(.-)%s*$") end
        min_count = tonumber(min_count) or 1 -- default to 1 if no minimum count was provided
        if item_name then
            local currentSetTable = BagWardenData.itemSets[BagWardenData.currentSet]
            for i, item in ipairs(currentSetTable) do
                if item.name == item_name then
                    print(item_name .. " is already in the current set.")
                    return
                end
            end
            table.insert(currentSetTable, { name = item_name, minCount = min_count })
            print("Added " .. item_name .. " to the current set.")
            CheckItems()
        else
            print("Invalid item name: " .. item_name)
        end
    elseif cmd == "remove" then
        local item_name = rest:match("^(.+)$")
        if item_name then 
            item_name = item_name:match("^%s*(.-)%s*$") 
        end
        local currentSetTable = BagWardenData.itemSets[BagWardenData.currentSet]
        for i = #currentSetTable, 1, -1 do
            if currentSetTable[i].name == item_name then
                table.remove(currentSetTable, i)
                break  -- assuming each item name is unique within a set
            end
        end
        CheckItems()
        print("Removed " .. item_name .. " from the item check list.")
    elseif cmd == "load" then
        local setName = rest:match("^(.+)$")
        if setName then
            setName = setName:match("^%s*(.-)%s*$") -- Remove leading and trailing spaces
            if setName then
                BagWardenData.currentSet = setName
                print("Loaded item check list from set: " .. setName)
                if BagWardenFrame:IsShown() then
                    CheckItems()
                end
            else
                print("Set not found: " .. setName)
            end
        else
            print("Invalid set name. Use: /bw load <set_name>")
        end
    elseif cmd == "deleteset" then
        local setName = rest:match("^%s*(.-)%s*$")
        BagWardenData.itemSets[setName] = nil
        BagWardenData.currentSet = "Default"
        print("Deleted set: " .. setName)
     elseif cmd == "createset" then
        local setName = rest:match("^%s*(.-)%s*$")
        if BagWardenData.itemSets[setName] then
            print("Set with the same name already exists: " .. setName)
        else
            BagWardenData.currentSet = setName
            BagWardenData.itemSets[setName] = {}
            print("Created a new set: " .. setName)
            CheckItems()
        end
    elseif cmd == "list" then
        print("Saved sets:")
        for setName, set in pairs(BagWardenData.itemSets) do
            print(" - " .. setName)
        end
    elseif cmd == "reset" then
        BagWardenData = DeepCopy(DefaultData)
        print("Reset item check list to default.")
        if BagWardenFrame:IsShown() then
            CheckItems()
        end
    elseif cmd == "" then
        if BagWardenFrame:IsShown() then
            BagWardenFrame:Hide()
        else
            BagWardenFrame:Show()
            CheckItems()
        end
    elseif cmd == "help" then
        print("BagWarden commands:")
        print("/bw: Toggle visibility of the item check list.")
        print("/bw createset <set_name>: Create a new set with the given name.")
        print("/bw removeset <set_name>: Remove a set by its name.")        
        print("/bw add <item_name> <min_count>: Add an item to the check list. Minimum count is optional.")
        print("/bw remove <item_name>: Remove an item from the check list.")
        print("/bw load <set_name>: Load a set.")
        print("/bw list: List sets.")
        print("/bw reset: Reset the list to default items.")        
        print("/bw help: Show this help text.")
    else
        print("Invalid command. Use: /bw, /bw toggle, /bw add <item_name> <min_count>, /bw remove <item_name>, /bw save <set_name>, /bw load <set_name>, /bw list, /bw reset, or /bw help")
    end
end