local itemTexts = {}
local itemSets
local MIN_FRAME_WIDTH = 200
local MIN_FRAME_HEIGHT = 300
local AceGUI = LibStub("AceGUI-3.0")


local isImportFrameVisible = false
local importFrame = nil -- This will hold the reference to the import frame

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



local function ClearFrameItems()
    for _, itemText in ipairs(itemTexts) do
        itemText:Hide()
    end
    itemTexts = {}
end



local frame = CreateFrame("Frame")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local function GetItemLinkFromName(itemName, callback)
    local itemID = select(1, GetItemInfoInstant(itemName))
    if not itemID then
        return nil
    end

    local itemLink = select(2, GetItemInfo(itemID))
    if itemLink then
        callback(itemLink)
    else
        frame:SetScript("OnEvent", function(self, event, arg1)
            if event == "GET_ITEM_INFO_RECEIVED" and arg1 == itemID then
                itemLink = select(2, GetItemInfo(itemID))
                if itemLink then
                    callback(itemLink)
                end
                self:SetScript("OnEvent", nil)
            end
        end)
    end
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
        local count = GetItemCount(itemName)
        local itemText = itemTexts[i]

        if not itemText then
            itemText = BagWardenFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            itemText:SetText(itemName)
            itemText:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 15 - 30) 
            itemTexts[i] = itemText
        end

        local updateTooltip = function(itemLink)
            itemText:SetScript("OnEnter", function(self)
                if itemLink then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(itemLink)
                    GameTooltip:Show()
                end
            end)
        end

        GetItemLinkFromName(itemName, updateTooltip)

    
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


function CreateImportFrame()
    ImportFrame = AceGUI:Create("Frame")
    ImportFrame:SetTitle("Update Items")
    ImportFrame:SetStatusText("Enter items and minimum count, one per line.")
    ImportFrame:SetLayout("List") -- Change to a List layout to stack widgets vertically
    ImportFrame:SetWidth(500)
    ImportFrame:SetHeight(400)

    editbox = AceGUI:Create("MultiLineEditBox")
    editbox:SetLabel("Item List (Format: Item Name,Min Count)")
    editbox:DisableButton(true)
    editbox:SetFullWidth(true)
    editbox:SetNumLines(20)

    local itemData = ""
    local currentSetTable = BagWardenData.itemSets[BagWardenData.currentSet]
    for _, item in ipairs(currentSetTable) do
        itemData = itemData .. item.name .. "," .. item.minCount .. "\r\n"
    end
    editbox:SetText(itemData)
    ImportFrame:AddChild(editbox)

    local function ImportItems()    
        local itemsText = editbox:GetText()
        local currentSetTable = BagWardenData.itemSets[BagWardenData.currentSet]

        for i in pairs(currentSetTable) do
            currentSetTable[i] = nil
        end

        for line in itemsText:gmatch("[^\r\n]+") do
            local itemName, minCount = line:match("^(.-),(%d+)$")
            minCount = tonumber(minCount)
            table.insert(currentSetTable, { name = itemName, minCount = minCount })
            print("Added " .. minCount .. " " .. itemName .. " to the current set.")
        end
        CheckItems()
    end

    -- Create an import button
    local importBtn = AceGUI:Create("Button")
    importBtn:SetText("Save")
    importBtn:SetFullWidth(true)
    importBtn:SetCallback("OnClick", function() ImportItems() end)
    ImportFrame:AddChild(importBtn)

end

BagWardenFrame:RegisterEvent("BAG_UPDATE")
BagWardenFrame:SetScript("OnEvent", CheckItems)
BagWardenFrame:RegisterEvent("ADDON_LOADED")
BagWardenFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "BagWarden" then
        if not BagWardenData then
            BagWardenData = DeepCopy(DefaultData)
        end

        if BagWardenData.hidden ~= true then
            BagWardenFrame:Show()
        else
            BagWardenFrame:Hide()
        end
        CheckItems()
        CreateImportFrame()
        ImportFrame:Hide()

        BagWardenFrame:UnregisterEvent("ADDON_LOADED")
    end

    if event == "BAG_UPDATE" and not InCombatLockdown() then
        CheckItems()
    end 
end)



-- Create the toggle button
local toggleButton = CreateFrame("Button", nil, BagWardenFrame, "UIPanelButtonTemplate")
toggleButton:SetPoint("TOPRIGHT", BagWardenFrame, "TOPRIGHT", -10, -10) -- Right align at 10 pixels from the right edge
toggleButton:SetSize(60, 22)
toggleButton:SetText('Update')
toggleButton:SetScript("OnClick", function()

    if ImportFrame:IsShown() then
        ImportFrame:Hide()
    else
        local itemData = ""
        local currentSetTable = BagWardenData.itemSets[BagWardenData.currentSet]
        for _, item in ipairs(currentSetTable) do
            itemData = itemData .. item.name .. "," .. item.minCount .. "\r\n"
        end
        editbox:SetText(itemData)    
        ImportFrame:Show()
    end

end)



SLASH_BagWarden1 = "/bgw"
SlashCmdList["BagWarden"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")

    if cmd == "add" then
        local item_name, min_count = rest:match("(.*)%s(%d+)$")
        if item_name then item_name = item_name:match("^%s*(.-)%s*$") end
        min_count = tonumber(min_count) or 1
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

        -- Clear all previous item texts and update the frame with the new list.
        for _, itemText in ipairs(itemTexts) do
            itemText:Hide()
        end
        itemTexts = {}
        CheckItems()
    
        print("Removed " .. item_name .. " from the item check list.")
    elseif cmd == "load" then
        local setName = rest:match("^(.+)$")
        if setName then
            ClearFrameItems()  -- Clear the frame before loading a new set
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
        CheckItems()        
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
            BagWardenData.hidden = true

        else
            BagWardenFrame:Show()
            BagWardenData.hidden = false
            CheckItems()
        end

    elseif cmd == "help" then
        print("BagWarden commands:")
        print("/bgw: Toggle visibility of the item check list.")
        print("/bgw createset <set_name>: Create a new set with the given name.")
        print("/bgw removeset <set_name>: Remove a set by its name.")        
        print("/bgw add <item_name> <min_count>: Add an item to the check list. Minimum count is optional.")
        print("/bgw remove <item_name>: Remove an item from the check list.")
        print("/bgw load <set_name>: Load a set.")
        print("/bgw list: List sets.")
        print("/bgw reset: Reset the list to default items.")        
        print("/bgw help: Show this help text.")
    else
        print("Invalid command")
    end
end



