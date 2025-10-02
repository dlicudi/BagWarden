local ADDON_NAME = "BagWarden"

-- Removed recipe database - using custom sets only

local AceGUI = LibStub("AceGUI-3.0")

local EXPORT_DELIMITER = "~"

local function splitByDelimiter(str, delimiter)
    local results = {}
    local startPos = 1
    local delimStart, delimEnd = string.find(str, delimiter, startPos, true)

    while delimStart do
        table.insert(results, string.sub(str, startPos, delimStart - 1))
        startPos = delimEnd + 1
        delimStart, delimEnd = string.find(str, delimiter, startPos, true)
    end

    table.insert(results, string.sub(str, startPos))
    return results
end

-- State
local mainWindow
local currentSelection = nil
local searchFilter = ""

local function ensureData()
    if not BagWardenData then
        BagWardenData = {
            itemSets = {
                Default = {}
            }
        }
    end
    BagWardenData.itemSets = BagWardenData.itemSets or {}
end

-- Find item ID by searching BagSync's cached data or the client cache
local itemNameToIDCache = {}

local function findItemIDByName(itemName)
    -- Clean the item name
    local cleanName = itemName:gsub("%[(.-)%]", "%1"):lower()

    -- Check our cache first
    if itemNameToIDCache[cleanName] then
        return itemNameToIDCache[cleanName]
    end

    -- Try GetItemInfo first (fast path if item is already cached in WoW client)
    local _, link = GetItemInfo(cleanName)
    if link then
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID then
            itemNameToIDCache[cleanName] = itemID
            return itemID
        end
    end

    -- Try to use BagSync's item cache if available
    if _G.BSYC and _G.BSYC.Data and _G.BSYC.Data.__cache and _G.BSYC.Data.__cache.items then
        for itemID, cacheObj in pairs(_G.BSYC.Data.__cache.items) do
            if cacheObj.itemName and cacheObj.itemName:lower() == cleanName then
                itemNameToIDCache[cleanName] = itemID
                return itemID
            end
        end
    end

    -- Last resort: search through stored item IDs in BagSync database
    -- BagSync stores items as "itemID;count" format
    if BagSyncDB then
        for realmName, realmData in pairs(BagSyncDB) do
            if type(realmData) == "table" and not realmName:match("§") then
                for charName, charData in pairs(realmData) do
                    if type(charData) == "table" and not charName:match("§") then
                        -- Check bags
                        if charData.bag then
                            for bagID, bagData in pairs(charData.bag) do
                                if type(bagData) == "table" then
                                    for _, itemString in ipairs(bagData) do
                                        if itemString then
                                            -- Extract item ID (format is "itemID;count" or "itemID;count^opts")
                                            local itemID = tonumber(itemString:match("^(%d+)"))
                                            if itemID then
                                                -- Get the name for this ID
                                                local name = C_Item.GetItemNameByID(itemID)
                                                if name and name:lower() == cleanName then
                                                    itemNameToIDCache[cleanName] = itemID
                                                    C_Item.RequestLoadItemDataByID(itemID)
                                                    return itemID
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- Enhanced item link retrieval
local function getItemLinkEnhanced(itemName)
    -- Clean the item name
    local cleanName = itemName:gsub("%[(.-)%]", "%1")

    -- Try GetItemInfo first (works if item is cached)
    local itemLink = select(2, GetItemInfo(cleanName))
    if itemLink then
        return itemLink
    end

    -- Try to find item ID by name
    local itemID = findItemIDByName(cleanName)
    if itemID then
        -- Request the item data to be loaded
        C_Item.RequestLoadItemDataByID(itemID)
        -- Try to get the link again (might be available now)
        itemLink = select(2, GetItemInfo(itemID))
        return itemLink
    end

    return nil
end

local function getItemsForSelection(value)
    -- Custom set
    if value:match("^set_") then
        local setName = value:gsub("^set_", "")
        local items = BagWardenData.itemSets[setName] or {}
        return items, setName
    end

    return {}, "Unknown"
end

local function buildTree()
    local tree = {}

    -- My Sets - filter by search
    for setName in pairs(BagWardenData.itemSets) do
        if searchFilter == "" or setName:lower():find(searchFilter:lower(), 1, true) then
            table.insert(tree, {
                value = "set_" .. setName,
                text = setName
            })
        end
    end
    table.sort(tree, function(a,b) return a.text < b.text end)

    return tree
end

local function showImportDialog()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Import Sets")
    frame:SetWidth(500)
    frame:SetHeight(400)
    frame:SetLayout("Fill")
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("Paste import strings (one set per line):")
    editBox:SetFullWidth(true)
    editBox:SetFullHeight(true)
    editBox:SetMaxLetters(0)
    frame:AddChild(editBox)

    editBox:SetCallback("OnEnterPressed", function(widget)
        local text = widget:GetText()
        if text and text ~= "" then
            local imported = 0
            local overwritten = 0

            -- Split by newlines and process each line
            for line in text:gmatch("[^\r\n]+") do
                line = line:match("^%s*(.-)%s*$") -- Trim whitespace
                if line ~= "" then
                    local parts = splitByDelimiter(line, EXPORT_DELIMITER)

                    if #parts > 0 then
                        local setName = parts[1]
                        local wasOverwritten = BagWardenData.itemSets[setName] ~= nil

                        BagWardenData.itemSets[setName] = {}

                        for i = 2, #parts do
                            local itemName, qty = parts[i]:match("^(.+):(%d+)$")
                            if itemName and qty then
                                -- Try to get item link for better display and tooltips
                                local itemLink = getItemLinkEnhanced(itemName)
                                local displayName = itemLink or itemName

                                table.insert(BagWardenData.itemSets[setName], {
                                    name = displayName,
                                    minCount = tonumber(qty) or 0
                                })
                            end
                        end

                        imported = imported + 1
                        if wasOverwritten then
                            overwritten = overwritten + 1
                        end
                    end
                end
            end

            if mainWindow and mainWindow.tree then
                mainWindow.tree:SetTree(buildTree())
            end
            frame:Hide()

            if imported > 0 then
                print(string.format("BagWarden: Imported %d set(s)", imported))
                if overwritten > 0 then
                    print(string.format("BagWarden: Warning - %d existing set(s) were overwritten", overwritten))
                end
            else
                print("BagWarden: No valid sets found to import")
            end
        end
    end)

    frame:Show()
end

local function showExportDialog()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Export All Sets")
    frame:SetWidth(500)
    frame:SetHeight(400)
    frame:SetLayout("Fill")
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    -- Build export string for all sets
    local exportLines = {}
    for setName, items in pairs(BagWardenData.itemSets) do
        -- Skip empty sets
        if #items > 0 then
            local parts = {setName}
            for _, item in ipairs(items) do
                -- Strip color codes and item link formatting from item names
                local cleanName = item.name

                -- If it's an item link, extract just the name
                if cleanName:match("|H") then
                    -- Extract item name from link format: |cXXXXXXXX|Hitem:...|h[Name]|h|r
                    local extractedName = cleanName:match("%[(.-)%]")
                    if extractedName then
                        cleanName = extractedName
                    else
                        -- Fallback: strip all formatting manually
                        cleanName = cleanName:gsub("|c%x%x%x%x%x%x%x%x", "")
                        cleanName = cleanName:gsub("|H.-|h", "")
                        cleanName = cleanName:gsub("|h", "")
                        cleanName = cleanName:gsub("|r", "")
                        cleanName = cleanName:gsub("%[(.-)%]", "%1")
                    end
                else
                    -- Plain text - remove brackets if present
                    if cleanName:sub(1,1) == "[" and cleanName:sub(-1) == "]" then
                        cleanName = cleanName:sub(2, -2)
                    end
                end

                -- Remove any newline/control characters that might be in the name
                cleanName = cleanName:gsub("[\r\n]", "")

                table.insert(parts, cleanName .. ":" .. (item.minCount or 0))
            end
            table.insert(exportLines, table.concat(parts, EXPORT_DELIMITER))
        end
    end

    table.sort(exportLines)
    local exportString = table.concat(exportLines, "\n")

    -- Store in a global variable so it can be accessed
    _G.BagWardenExportData = exportString

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("Copy export strings (Ctrl+A, Ctrl+C):")
    editBox:SetFullWidth(true)
    editBox:SetFullHeight(true)
    editBox:SetText(exportString)
    editBox:SetMaxLetters(0)
    editBox:DisableButton(true)

    -- Disable editing to prevent corruption
    editBox.editBox:SetEnabled(true)
    editBox.editBox:SetAutoFocus(false)

    frame:AddChild(editBox)

    -- Auto-select all text
    C_Timer.After(0.1, function()
        editBox:SetFocus()
        editBox.editBox:HighlightText()
        editBox.editBox:SetCursorPosition(0)
    end)

    frame:Show()
end

local function updateContent()
    if not mainWindow or not currentSelection then
        return
    end

    local tree = mainWindow.tree
    if not tree then
        return
    end

    tree:ReleaseChildren()
    tree:PauseLayout()

    -- Button bar at top
    local buttonBar = AceGUI:Create("SimpleGroup")
    buttonBar:SetFullWidth(true)
    buttonBar:SetLayout("Flow")
    buttonBar.frame:EnableMouse(false)

    local newSetBtn = AceGUI:Create("Button")
    newSetBtn:SetText("New Set")
    newSetBtn:SetWidth(100)
    newSetBtn:SetCallback("OnClick", function()
        StaticPopup_Show("BAGWARDEN_NEW_SET")
    end)
    buttonBar:AddChild(newSetBtn)

    local renameSetBtn = AceGUI:Create("Button")
    renameSetBtn:SetText("Rename Set")
    renameSetBtn:SetWidth(80)
    renameSetBtn:SetCallback("OnClick", function()
        if currentSelection and currentSelection:match("^set_") then
            local setName = currentSelection:gsub("^set_", "")
            StaticPopup_Show("BAGWARDEN_RENAME_SET", nil, nil, setName)
        end
    end)
    buttonBar:AddChild(renameSetBtn)

    local deleteSetBtn = AceGUI:Create("Button")
    deleteSetBtn:SetText("Delete Set")
    deleteSetBtn:SetWidth(100)
    deleteSetBtn:SetCallback("OnClick", function()
        if currentSelection and currentSelection:match("^set_") then
            local setName = currentSelection:gsub("^set_", "")
            StaticPopup_Show("BAGWARDEN_DELETE_SET", setName, nil, setName)
        end
    end)
    buttonBar:AddChild(deleteSetBtn)

    local importBtn = AceGUI:Create("Button")
    importBtn:SetText("Import Sets")
    importBtn:SetWidth(100)
    importBtn:SetCallback("OnClick", function()
        showImportDialog()
    end)
    buttonBar:AddChild(importBtn)

    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText("Export Sets")
    exportBtn:SetWidth(100)
    exportBtn:SetCallback("OnClick", function()
        showExportDialog()
    end)
    buttonBar:AddChild(exportBtn)

    tree:AddChild(buttonBar)

    local items, displayName = getItemsForSelection(currentSelection)

    -- Add item controls
    local addGroup = AceGUI:Create("SimpleGroup")
    addGroup:SetFullWidth(true)
    addGroup:SetLayout("Flow")

    -- Disable any highlight on the add group
    addGroup.frame:EnableMouse(false)

    local editBox = AceGUI:Create("EditBox")
    editBox:SetLabel("Add Item")
    editBox:SetRelativeWidth(0.7)
    editBox:SetText("")  -- Ensure it starts empty
    editBox:SetCallback("OnEnterPressed", function(widget, _, text)
        if text ~= "" then
            table.insert(items, {name = text, minCount = 0})
            widget:SetText("")
            updateContent()
        end
    end)
    addGroup:AddChild(editBox)

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText("Add")
    addBtn:SetRelativeWidth(0.3)
    addBtn:SetCallback("OnClick", function()
        local text = editBox:GetText()
        if text ~= "" then
            table.insert(items, {name = text, minCount = 0})
            editBox:SetText("")
            updateContent()
        end
    end)
    addGroup:AddChild(addBtn)

    tree:AddChild(addGroup)

    -- Item list with scroll
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("List")
    tree:AddChild(scroll)

    -- Make scroll area accept item drops
    scroll.frame:RegisterForDrag("LeftButton")
    scroll.frame:SetScript("OnReceiveDrag", function(self)
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" then
            ClearCursor()
            if itemLink then
                -- Get clean name for duplicate checking
                local itemName = GetItemInfo(itemLink)
                local cleanName = itemName
                if cleanName then
                    cleanName = cleanName:gsub("|c%x%x%x%x%x%x%x%x", "")
                    cleanName = cleanName:gsub("|r", "")
                    cleanName = cleanName:gsub("|H.-|h", "")
                    cleanName = cleanName:gsub("%[(.-)%]", "%1")

                    -- Check for duplicates
                    local isDuplicate = false
                    for _, existingItem in ipairs(items) do
                        local existingClean = existingItem.name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("%[(.-)%]", "%1")
                        if existingClean == cleanName then
                            isDuplicate = true
                            break
                        end
                    end

                    if not isDuplicate then
                        -- Store the item link for proper tooltips!
                        table.insert(items, {name = itemLink, minCount = 1})
                        updateContent()
                    end
                end
            end
        end
    end)
    scroll.frame:SetScript("OnMouseUp", function(self)
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" then
            ClearCursor()
            if itemLink then
                -- Get clean name for duplicate checking
                local itemName = GetItemInfo(itemLink)
                local cleanName = itemName
                if cleanName then
                    cleanName = cleanName:gsub("|c%x%x%x%x%x%x%x%x", "")
                    cleanName = cleanName:gsub("|r", "")
                    cleanName = cleanName:gsub("|H.-|h", "")
                    cleanName = cleanName:gsub("%[(.-)%]", "%1")

                    -- Check for duplicates
                    local isDuplicate = false
                    for _, existingItem in ipairs(items) do
                        local existingClean = existingItem.name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("%[(.-)%]", "%1")
                        if existingClean == cleanName then
                            isDuplicate = true
                            break
                        end
                    end

                    if not isDuplicate then
                        -- Store the item link for proper tooltips!
                        table.insert(items, {name = itemLink, minCount = 1})
                        updateContent()
                    end
                end
            end
        end
    end)

    for i, item in ipairs(items) do
        -- Capture the index in a local variable for the closures
        local itemIndex = i
        local currentItem = item

        local count = GetItemCount(currentItem.name)
        local isMet = count >= (currentItem.minCount or 0)
        local color = isMet and {0.2, 0.9, 0.2} or {1, 0.2, 0.2}

        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")

        -- Set fixed height for consistent row size
        row:SetHeight(22)

        -- Create background highlight texture (like BagSync)
        local highlight = row.frame:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints(row.frame)
        highlight:SetColorTexture(0, 1, 0, 0.2)
        highlight:SetBlendMode("ADD")
        highlight:Hide()

        -- Make the row frame clickable/hoverable
        row.frame:EnableMouse(true)
        row.frame:SetScript("OnEnter", function(self)
            highlight:Show()

            -- Show tooltip
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local itemName = currentItem.name:match("%[(.-)%]") or currentItem.name
            GameTooltip:ClearLines()

            local itemLink = nil
            if currentItem.name:match("|H") then
                itemLink = currentItem.name
            else
                itemLink = getItemLinkEnhanced(itemName)
            end

            if itemLink then
                GameTooltip:SetHyperlink(itemLink)
            else
                GameTooltip:SetText(currentItem.name, 1, 1, 1)
                GameTooltip:AddLine("Count in bags: " .. count, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        row.frame:SetScript("OnLeave", function()
            highlight:Hide()
            GameTooltip:Hide()
        end)

        -- Add icon
        local icon = AceGUI:Create("Icon")
        icon:SetWidth(20)
        icon:SetHeight(20)

        -- Get item texture/icon
        local itemID = findItemIDByName(currentItem.name:match("%[(.-)%]") or currentItem.name)
        if itemID then
            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
            if texture then
                icon:SetImage(texture)
            else
                icon:SetImage("Interface\\Icons\\INV_Misc_QuestionMark")
            end
        else
            icon:SetImage("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        icon:SetImageSize(18, 18)
        icon.frame:EnableMouse(false)  -- Let mouse events pass through to row
        row:AddChild(icon)

        -- Add spacing between icon and text
        local spacer = AceGUI:Create("Label")
        spacer:SetWidth(8)
        spacer:SetText("")
        spacer.label:EnableMouse(false)
        row:AddChild(spacer)

        local nameLabel = AceGUI:Create("Label")
        nameLabel:SetRelativeWidth(0.48)
        nameLabel:SetText(currentItem.name)
        nameLabel:SetColor(unpack(color))
        nameLabel.label:SetFont(nameLabel.label:GetFont(), 12)
        nameLabel.label:EnableMouse(false)  -- Let mouse events pass through to row
        row:AddChild(nameLabel)

        local countLabel = AceGUI:Create("Label")
        countLabel:SetRelativeWidth(0.25)
        countLabel:SetText(string.format("%d/%d", count, currentItem.minCount or 0))
        countLabel:SetColor(unpack(color))
        countLabel.label:SetFont(countLabel.label:GetFont(), 12)
        countLabel.label:EnableMouse(false)  -- Let mouse events pass through to row
        row:AddChild(countLabel)

        local minusLbl = AceGUI:Create("InteractiveLabel")
        minusLbl:SetWidth(25)
        minusLbl:SetText("[-]")
        minusLbl:SetColor((currentItem.minCount or 0) > 0 and 1 or 0.5, 0.82, 0)
        minusLbl.label:SetFont(minusLbl.label:GetFont(), 12)
        if (currentItem.minCount or 0) > 0 then
            minusLbl:SetCallback("OnClick", function()
                currentItem.minCount = (currentItem.minCount or 0) - 1
                updateContent()
            end)
        end
        row:AddChild(minusLbl)

        local plusLbl = AceGUI:Create("InteractiveLabel")
        plusLbl:SetWidth(25)
        plusLbl:SetText("[+]")
        plusLbl:SetColor(0, 1, 0)
        plusLbl.label:SetFont(plusLbl.label:GetFont(), 12)
        plusLbl:SetCallback("OnClick", function()
            currentItem.minCount = (currentItem.minCount or 0) + 1
            updateContent()
        end)
        row:AddChild(plusLbl)

        local delLbl = AceGUI:Create("InteractiveLabel")
        delLbl:SetWidth(25)
        delLbl:SetText("[×]")
        delLbl:SetColor(1, 0, 0)
        delLbl.label:SetFont(delLbl.label:GetFont(), 12)
        delLbl:SetCallback("OnClick", function()
            table.remove(items, itemIndex)
            updateContent()
        end)
        row:AddChild(delLbl)

        scroll:AddChild(row)
    end

    tree:ResumeLayout()
    tree:DoLayout()

    mainWindow:SetStatusText(displayName .. " • " .. #items .. " items")
end

local function refreshTree()
    if not mainWindow or not mainWindow.tree then return end
    mainWindow.tree:SetTree(buildTree())
    if currentSelection then
        updateContent()
    end
end

local function createWindow()
    if mainWindow then
        mainWindow:Show()
        return
    end

    ensureData()

    local window = AceGUI:Create("Frame")
    window:SetTitle("BagWarden")
    window:SetStatusText("")
    window:SetLayout("Fill")
    window:SetWidth(700)
    window:SetHeight(500)
    window:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)

    local tree = AceGUI:Create("TreeGroup")
    tree:SetTree(buildTree())
    tree:SetFullWidth(true)
    tree:SetFullHeight(true)
    tree:SetLayout("Flow")
    tree:SetCallback("OnGroupSelected", function(_, _, selection)
        -- TreeGroup passes path with \001 separator
        local value = selection
        if type(selection) == "string" then
            local parts = {}
            for part in selection:gmatch("[^\001]+") do
                parts[#parts + 1] = part
            end
            value = parts[#parts] or selection
        elseif type(selection) == "table" then
            value = selection[#selection]
        end
        currentSelection = value
        updateContent()
    end)

    window:AddChild(tree)

    -- Add search box below the tree panel
    local searchFrame = CreateFrame("EditBox", nil, window.frame, "InputBoxTemplate")
    searchFrame:SetSize(160, 20)
    searchFrame:SetPoint("BOTTOMLEFT", tree.treeframe, "BOTTOMLEFT", 10, 5)
    searchFrame:SetAutoFocus(false)
    searchFrame:SetScript("OnTextChanged", function(self)
        searchFilter = self:GetText()
        tree:SetTree(buildTree())
    end)
    searchFrame:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local searchLabel = searchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("BOTTOMLEFT", searchFrame, "TOPLEFT", 0, 2)
    searchLabel:SetText("Search:")

    window.searchFrame = searchFrame

    mainWindow = window
    mainWindow.tree = tree

    -- Select first set if available
    local firstSet = next(BagWardenData.itemSets)
    if firstSet then
        tree:SelectByPath("set_" .. firstSet)
    end
end

-- StaticPopup dialogs
StaticPopupDialogs["BAGWARDEN_NEW_SET"] = {
    text = "Enter name for new set:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    OnShow = function(self)
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local text = self.editBox:GetText()
        if text and text ~= "" then
            if BagWardenData.itemSets[text] then
                print("BagWarden: A set named '" .. text .. "' already exists!")
            else
                BagWardenData.itemSets[text] = {}
                refreshTree()
                currentSelection = "set_" .. text
                updateContent()
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopup_OnClick(parent, 1)
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["BAGWARDEN_RENAME_SET"] = {
    text = "Enter new name for set:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    OnShow = function(self, oldName)
        self.editBox:SetText(oldName)
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self, oldName)
        local newName = self.editBox:GetText()
        if newName and newName ~= "" and newName ~= oldName then
            if BagWardenData.itemSets[newName] then
                print("BagWarden: A set named '" .. newName .. "' already exists!")
            else
                BagWardenData.itemSets[newName] = BagWardenData.itemSets[oldName]
                BagWardenData.itemSets[oldName] = nil
                refreshTree()
                currentSelection = "set_" .. newName
                updateContent()
            end
        end
    end,
    EditBoxOnEnterPressed = function(self, data)
        local parent = self:GetParent()
        StaticPopup_OnClick(parent, 1)
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["BAGWARDEN_DELETE_SET"] = {
    text = "Delete set '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data then
            BagWardenData.itemSets[data] = nil
            currentSelection = nil
            refreshTree()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("BAG_UPDATE")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ensureData()
        createWindow()
        if BagWardenData.hidden then
            mainWindow:Hide()
        end
    elseif event == "BAG_UPDATE" then
        if mainWindow and mainWindow:IsShown() then
            updateContent()
        end
    end
end)

-- Commands
SLASH_BagWarden1 = "/bw"
SLASH_BagWarden2 = "/bgw"
SlashCmdList["BagWarden"] = function()
    if not mainWindow then
        createWindow()
    end

    if mainWindow:IsShown() then
        mainWindow:Hide()
        BagWardenData.hidden = true
    else
        mainWindow:Show()
        BagWardenData.hidden = false
    end
end
