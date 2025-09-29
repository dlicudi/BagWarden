local ADDON_NAME = ...
local MIN_FRAME_WIDTH = 420
local MIN_FRAME_HEIGHT = 380

local function decorateStepButton(button, isPlus)
    local frame = button and button.frame
    if not frame then
        return
    end

    local base = isPlus and "Interface\\Buttons\\UI-PlusButton" or "Interface\\Buttons\\UI-MinusButton"

    button:SetText("")
    frame:SetNormalTexture(base .. "-Up")
    frame:SetPushedTexture(base .. "-Down")
    frame:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    frame:SetDisabledTexture(base .. "-Disabled")

    local disabledTexture = frame:GetDisabledTexture()
    if disabledTexture then
        disabledTexture:SetDesaturated(true)
        disabledTexture:SetAlpha(0.6)
    end
end

local AceGUI = LibStub("AceGUI-3.0")

local ui = {
    frame = nil,
    setDropdown = nil,
    itemScroll = nil,
}

local function trim(text)
    if not text then
        return ""
    end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function pluralSuffix(count)
    return count == 1 and "" or "s"
end

local function ensureData()
    if not BagWardenData then
        BagWardenData = DeepCopy(DefaultData)
    end

    BagWardenData.currentSet = BagWardenData.currentSet or "Default"
    BagWardenData.itemSets = BagWardenData.itemSets or {}
    BagWardenData.itemSets["Default"] = BagWardenData.itemSets["Default"] or {}
end

local function sortedSetNames()
    ensureData()
    local names = {}
    for setName in pairs(BagWardenData.itemSets) do
        table.insert(names, setName)
    end
    table.sort(names)
    return names
end

local function currentSet()
    ensureData()
    BagWardenData.itemSets[BagWardenData.currentSet] = BagWardenData.itemSets[BagWardenData.currentSet] or {}
    return BagWardenData.itemSets[BagWardenData.currentSet]
end

local RefreshUI
local ShowFrame
local HideFrame
local ShowImportFrame

StaticPopupDialogs["BAGWARDEN_NEW_SET"] = {
    text = "Enter a name for the new set:",
    button1 = CREATE,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 32,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local setName = trim(self.editBox:GetText())
        if setName == "" then
            print("BagWarden: Set name cannot be empty.")
            return
        end

        ensureData()

        if BagWardenData.itemSets[setName] then
            print("BagWarden: A set named '" .. setName .. "' already exists.")
            return
        end

        BagWardenData.itemSets[setName] = {}
        BagWardenData.currentSet = setName
        print("BagWarden: Created set '" .. setName .. "'.")
        RefreshUI()
        ShowFrame()
    end,
    EditBoxOnEnterPressed = function(editBox)
        local parent = editBox:GetParent()
        StaticPopup_OnClick(parent, 1)
        parent:Hide()
    end,
}

StaticPopupDialogs["BAGWARDEN_DELETE_SET"] = {
    text = "Delete set '%s'?",
    button1 = DELETE,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self, data)
        ensureData()
        local setName = data or self.data

        if not setName or setName == "" then
            print("BagWarden: No set selected to delete.")
            return
        end

        if setName == "Default" then
            print("BagWarden: Cannot delete the Default set.")
            return
        end

        if not BagWardenData.itemSets[setName] then
            print("BagWarden: Set not found: " .. setName)
            return
        end

        BagWardenData.itemSets[setName] = nil
        if BagWardenData.currentSet == setName then
            BagWardenData.currentSet = "Default"
        end

        print("BagWarden: Deleted set '" .. setName .. "'.")
        RefreshUI()
    end,
    OnShow = function(self, data)
        self.text:SetFormattedText("Delete set '%s'?", data)
        self.data = data
    end,
    OnHide = function(self)
        self.data = nil
    end,
}

local function refreshDropdown()
    if not ui.setDropdown then
        return
    end

    local options = {}
    local order = {}
    for _, name in ipairs(sortedSetNames()) do
        options[name] = name
        table.insert(order, name)
    end

    ui.setDropdown:SetList(options, order)
    ui.setDropdown:SetValue(BagWardenData.currentSet)
end

local function attachTooltip(widget, itemID)
    if not itemID then
        return
    end

    widget:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(itemID)
        GameTooltip:Show()
    end)

    widget:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function updateItems()
    if not ui.itemScroll or not ui.frame then
        return
    end

    local setName = BagWardenData.currentSet
    local trackedItems = currentSet()

    ui.itemScroll:ReleaseChildren()

    if #trackedItems == 0 then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetFullWidth(true)
        emptyLabel:SetText("No items tracked. Click 'Edit Items' to add some.")
        ui.itemScroll:AddChild(emptyLabel)
    else
        for _, item in ipairs(trackedItems) do
            item.minCount = item.minCount or 0
            local count = GetItemCount(item.name)

            local row = AceGUI:Create("SimpleGroup")
            row:SetFullWidth(true)
            row:SetLayout("Flow")
            row:SetAutoAdjustHeight(false)
            row:SetHeight(28)

            local nameLabel = AceGUI:Create("InteractiveLabel")
            nameLabel:SetRelativeWidth(0.65)
            nameLabel:SetText(string.format("%s: %d/%d", item.name, count, item.minCount))
            nameLabel:SetColor(count >= item.minCount and 0.2 or 1, count >= item.minCount and 0.9 or 0.2, 0.2)
            nameLabel:SetFontObject(count >= item.minCount and GameFontHighlight or GameFontNormal)
            attachTooltip(nameLabel, GetItemInfoInstant(item.name))
            row:AddChild(nameLabel)

            local minusButton = AceGUI:Create("Button")
            minusButton:SetWidth(24)
            minusButton:SetHeight(22)
            minusButton:SetCallback("OnClick", function()
                if (item.minCount or 0) > 0 then
                    item.minCount = item.minCount - 1
                    updateItems()
                end
            end)
            decorateStepButton(minusButton, false)
            minusButton:SetDisabled((item.minCount or 0) <= 0)
            row:AddChild(minusButton)

            local targetLabel = AceGUI:Create("Label")
            targetLabel:SetWidth(56)
            targetLabel:SetText(string.format("%d", item.minCount))
            targetLabel:SetJustifyH("CENTER")
            targetLabel:SetFontObject(GameFontHighlight)
            row:AddChild(targetLabel)

            local plusButton = AceGUI:Create("Button")
            plusButton:SetWidth(24)
            plusButton:SetHeight(22)
            plusButton:SetCallback("OnClick", function()
                item.minCount = (item.minCount or 0) + 1
                updateItems()
            end)
            decorateStepButton(plusButton, true)
            row:AddChild(plusButton)

            ui.itemScroll:AddChild(row)
        end
    end

    ui.frame:SetStatusText(string.format("%s • %d item%s", setName, #trackedItems, pluralSuffix(#trackedItems)))
end

RefreshUI = function()
    if not ui.frame then
        return
    end

    refreshDropdown()
    updateItems()
end

local function saveImportList(editBox, statusLabel, parentFrame)
    ensureData()
    local text = editBox:GetText() or ""
    local setName = BagWardenData.currentSet
    local newItems = {}
    local invalidLines = {}

    local lineNumber = 0
    for line in text:gmatch("[^\r\n]+") do
        lineNumber = lineNumber + 1
        local cleaned = trim(line)
        if cleaned ~= "" then
            local itemName, minCount = cleaned:match("^(.-),%s*(%d+)$")
            if itemName and minCount then
                table.insert(newItems, {
                    name = trim(itemName),
                    minCount = tonumber(minCount),
                })
            else
                if not cleaned:find(",") then
                    table.insert(newItems, {
                        name = cleaned,
                        minCount = 0,
                    })
                else
                    local onlyName = cleaned:match("^(.-),%s*$")
                    if onlyName then
                        onlyName = trim(onlyName)
                    end

                    if onlyName and onlyName ~= "" then
                        table.insert(newItems, {
                            name = onlyName,
                            minCount = 0,
                        })
                    else
                        table.insert(invalidLines, string.format("%d: %s", lineNumber, cleaned))
                    end
                end
            end
        end
    end

    BagWardenData.itemSets[setName] = newItems

    local statusMessage
    local statusColor = { 0.2, 0.9, 0.2 }

    if #invalidLines > 0 then
        statusColor = { 1, 0.3, 0.3 }
        statusMessage = "Skipped invalid lines:\n- " .. table.concat(invalidLines, "\n- ")
        print("BagWarden: Skipped invalid lines:")
        for _, bad in ipairs(invalidLines) do
            print(" - " .. bad)
        end
    else
        statusMessage = string.format("Saved %d item%s to set '%s'.", #newItems, pluralSuffix(#newItems), setName)
        if parentFrame then
            parentFrame:Hide()
        end
    end

    print("BagWarden: " .. statusMessage)

    if parentFrame and parentFrame.SetStatusText then
        parentFrame:SetStatusText(string.format("%s • %d item%s", setName, #newItems, pluralSuffix(#newItems)))
    end

    if statusLabel then
        statusLabel:SetColor(unpack(statusColor))
        statusLabel:SetText(statusMessage)
    end

    RefreshUI()
end

ShowImportFrame = function()
    ensureData()

    local importFrame = AceGUI:Create("Frame")
    importFrame:SetTitle("Edit Items")
    importFrame:SetLayout("Fill")
    importFrame:SetWidth(560)
    importFrame:SetHeight(460)
    importFrame:SetAutoAdjustHeight(false)
    importFrame:EnableResize(true)
    if importFrame.frame and importFrame.frame.SetResizeBounds then
        importFrame.frame:SetResizeBounds(420, 340, 960, 780)
    end

    importFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local setName = BagWardenData.currentSet

    local body = AceGUI:Create("SimpleGroup")
    body:SetFullWidth(true)
    body:SetFullHeight(true)
    body:SetLayout("List")
    importFrame:AddChild(body)

    local info = AceGUI:Create("Label")
    info:SetFullWidth(true)
    info:SetText("One per line: Item Name[,Min Count] — count optional")
    body:AddChild(info)

    local summaryLabel = AceGUI:Create("Label")
    summaryLabel:SetFullWidth(true)
    summaryLabel:SetColor(0.7, 0.7, 0.7)
    summaryLabel:SetText("")
    body:AddChild(summaryLabel)

    local feedbackLabel = AceGUI:Create("Label")
    feedbackLabel:SetFullWidth(true)
    feedbackLabel:SetColor(0.7, 0.7, 0.7)
    feedbackLabel:SetText("")
    feedbackLabel:SetJustifyH("LEFT")
    body:AddChild(feedbackLabel)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("Items")
    editBox:SetFullWidth(true)
    editBox:DisableButton(true)

    local setItems = currentSet()
    local buffer = {}
    for _, item in ipairs(setItems) do
        local minCount = item.minCount or 0
        if minCount > 0 then
            table.insert(buffer, string.format("%s,%d", item.name, minCount))
        else
            table.insert(buffer, item.name)
        end
    end
    editBox:SetText(table.concat(buffer, "\n"))
    editBox:SetCallback("OnTextChanged", function(_, _, value)
        local total = 0
        for line in (value or ""):gmatch("[^\r\n]+") do
            if trim(line) ~= "" then
                total = total + 1
            end
        end
        summaryLabel:SetText(string.format("Entries detected: %d", total))
        summaryLabel:SetColor(0.7, 0.7, 0.7)
        feedbackLabel:SetText("")
        feedbackLabel:SetColor(0.7, 0.7, 0.7)
        importFrame:SetStatusText(string.format("%s • %d item%s", setName, total, pluralSuffix(total)))
    end)
    local initialCount = #setItems
    summaryLabel:SetText(string.format("Entries detected: %d", initialCount))
    importFrame:SetStatusText(string.format("%s • %d item%s", setName, initialCount, pluralSuffix(initialCount)))
    body:AddChild(editBox)

    local buttonRow = AceGUI:Create("SimpleGroup")
    buttonRow:SetFullWidth(true)
    buttonRow:SetLayout("Flow")
    body:AddChild(buttonRow)

    local saveButton = AceGUI:Create("Button")
    saveButton:SetText("Save")
    saveButton:SetAutoWidth(false)
    saveButton:SetWidth(180)
    saveButton:SetCallback("OnClick", function()
        saveImportList(editBox, feedbackLabel, importFrame)
    end)
    buttonRow:AddChild(saveButton)

    local cancelButton = AceGUI:Create("Button")
    cancelButton:SetText("Cancel")
    cancelButton:SetAutoWidth(false)
    cancelButton:SetWidth(180)
    cancelButton:SetCallback("OnClick", function()
        importFrame:Hide()
    end)
    buttonRow:AddChild(cancelButton)

    local spacer = AceGUI:Create("Label")
    spacer:SetWidth(1)
    spacer:SetText("")
    buttonRow:AddChild(spacer)

    local adjustingLayout = false

    local function adjustEditBoxHeight()
        if adjustingLayout then
            return
        end
        if not importFrame or not importFrame.frame then
            return
        end

        adjustingLayout = true

        local frameHeight = importFrame.frame:GetHeight() or 0
        local reserved = 0
        for _, widget in ipairs({ info, summaryLabel, feedbackLabel, buttonRow }) do
            if widget and widget.frame then
                reserved = reserved + (widget.frame:GetHeight() or 0)
            end
        end

        local padding = 90
        local desired = frameHeight - reserved - padding
        editBox:SetHeight(math.max(140, desired))
        importFrame:DoLayout()
        adjustingLayout = false
    end

    adjustEditBoxHeight()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, adjustEditBoxHeight)
    end

    if importFrame.frame and importFrame.frame.HookScript then
        importFrame.frame:HookScript("OnShow", function()
            adjustEditBoxHeight()
        end)
        importFrame.frame:HookScript("OnSizeChanged", function()
            adjustEditBoxHeight()
        end)
    end

    editBox:SetFocus()
end

local function buildMainFrame()
    if ui.frame then
        return
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("BagWarden")
    frame:SetStatusText("")
    frame:SetLayout("Fill")
    frame:SetWidth(MIN_FRAME_WIDTH)
    frame:SetHeight(MIN_FRAME_HEIGHT)
    frame:SetAutoAdjustHeight(false)
    frame:EnableResize(true)
    if frame.frame and frame.frame.SetResizeBounds then
        frame.frame:SetResizeBounds(MIN_FRAME_WIDTH, MIN_FRAME_HEIGHT, 840, 720)
    end

    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
        HideFrame()
    end)

    local body = AceGUI:Create("SimpleGroup")
    body:SetFullWidth(true)
    body:SetFullHeight(true)
    body:SetLayout("List")
    frame:AddChild(body)

    local setRow = AceGUI:Create("SimpleGroup")
    setRow:SetLayout("Flow")
    setRow:SetFullWidth(true)

    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetLabel("Item Set")
    dropdown:SetRelativeWidth(0.6)
    dropdown:SetCallback("OnValueChanged", function(_, _, value)
        if not value or value == "" then
            return
        end
        BagWardenData.currentSet = value
        updateItems()
    end)
    setRow:AddChild(dropdown)

    local newButton = AceGUI:Create("Button")
    newButton:SetText("New")
    newButton:SetRelativeWidth(0.2)
    newButton:SetCallback("OnClick", function()
        StaticPopup_Show("BAGWARDEN_NEW_SET")
    end)
    setRow:AddChild(newButton)

    local deleteButton = AceGUI:Create("Button")
    deleteButton:SetText("Delete")
    deleteButton:SetRelativeWidth(0.2)
    deleteButton:SetCallback("OnClick", function()
        local setName = BagWardenData.currentSet
        if setName == "Default" then
            print("BagWarden: Cannot delete the Default set.")
            return
        end
        StaticPopup_Show("BAGWARDEN_DELETE_SET", setName, nil, setName)
    end)
    setRow:AddChild(deleteButton)

    body:AddChild(setRow)

    local editButton = AceGUI:Create("Button")
    editButton:SetText("Edit Items")
    editButton:SetFullWidth(true)
    editButton:SetCallback("OnClick", ShowImportFrame)
    body:AddChild(editButton)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    body:AddChild(scroll)

    ui.frame = frame
    ui.setDropdown = dropdown
    ui.itemScroll = scroll

    local adjustingScroll = false
    local function adjustScrollHeight()
        if adjustingScroll then
            return
        end
        if not frame or not frame.frame then
            return
        end

        adjustingScroll = true

        local frameHeight = frame.frame:GetHeight() or 0
        local reserved = 0
        for _, widget in ipairs({ setRow, editButton }) do
            if widget and widget.frame then
                reserved = reserved + (widget.frame:GetHeight() or 0)
            end
        end

        local statusHeight = 0
        if frame.statustext and frame.statustext:GetHeight() then
            statusHeight = frame.statustext:GetHeight() + 8
        end

        local topInset = 0
        local bottomInset = 0
        if frame.frame and body.frame then
            local frameTop = frame.frame:GetTop()
            local bodyTop = body.frame:GetTop()
            if frameTop and bodyTop then
                topInset = math.max(0, frameTop - bodyTop)
            end

            local frameBottom = frame.frame:GetBottom()
            local bodyBottom = body.frame:GetBottom()
            if frameBottom and bodyBottom then
                bottomInset = math.max(0, bodyBottom - frameBottom)
            end
        end

        local padding = topInset + bottomInset + statusHeight + 20
        local desired = frameHeight - reserved - padding
        scroll:SetHeight(math.max(220, desired))
        frame:DoLayout()
        adjustingScroll = false
    end

    adjustScrollHeight()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, adjustScrollHeight)
    end

    if frame.frame and frame.frame.HookScript then
        frame.frame:HookScript("OnShow", function()
            adjustScrollHeight()
        end)
        frame.frame:HookScript("OnSizeChanged", function()
            adjustScrollHeight()
        end)
    end

    frame:Hide()
end

ShowFrame = function()
    ensureData()
    buildMainFrame()
    RefreshUI()
    ui.frame:Show()
    BagWardenData.hidden = false
end

HideFrame = function()
    if ui.frame then
        ui.frame:Hide()
    end
    if BagWardenData then
        BagWardenData.hidden = true
    end
end

local function toggleFrame()
    if not ui.frame or not ui.frame:IsShown() then
        ShowFrame()
    else
        HideFrame()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "BagWarden" then
        ensureData()
        buildMainFrame()
        RefreshUI()
        if BagWardenData.hidden then
            ui.frame:Hide()
        else
            ui.frame:Show()
        end
        eventFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "BAG_UPDATE" then
        if ui.frame and ui.frame:IsShown() then
            updateItems()
        end
    end
end)

SLASH_BagWarden1 = "/bgw"
SLASH_BagWarden2 = "/bw"
SlashCmdList["BagWarden"] = function(msg)
    ensureData()
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "add" then
        if rest == "" then
            print("BagWarden: Usage - /bw add <item name> [min count]")
            return
        end

        local namePart, countPart = rest:match("^(.-)%s+(%d+)$")
        local trimmedName
        local count

        if countPart then
            trimmedName = trim(namePart)
            count = tonumber(countPart)
        else
            trimmedName = trim(rest)
            count = 0
        end

        if not trimmedName or trimmedName == "" then
            print("BagWarden: Usage - /bw add <item name> [min count]")
            return
        end

        table.insert(currentSet(), { name = trimmedName, minCount = count })

        if count > 0 then
            print("BagWarden: Added '" .. trimmedName .. "' with minimum " .. count .. ".")
        else
            print("BagWarden: Added '" .. trimmedName .. "'. Use the +/- buttons to set a minimum.")
        end

        RefreshUI()
    elseif cmd == "remove" then
        local itemName = trim(rest)
        if itemName == "" then
            print("BagWarden: Specify the item name to remove.")
            return
        end

        local set = currentSet()
        for index = #set, 1, -1 do
            if set[index].name == itemName then
                table.remove(set, index)
            end
        end

        print("BagWarden: Removed '" .. itemName .. "' from the current set.")
        RefreshUI()
    elseif cmd == "load" then
        local setName = trim(rest)
        if setName == "" then
            print("BagWarden: Usage - /bw load <set name>")
            return
        end
        if not BagWardenData.itemSets[setName] then
            print("BagWarden: Set not found: " .. setName)
            return
        end
        BagWardenData.currentSet = setName
        print("BagWarden: Loaded set '" .. setName .. "'.")
        RefreshUI()
    elseif cmd == "createset" then
        StaticPopup_Show("BAGWARDEN_NEW_SET")
    elseif cmd == "deleteset" then
        local setName = trim(rest)
        if setName == "" then
            setName = BagWardenData.currentSet
        end
        if setName == "Default" then
            print("BagWarden: Cannot delete the Default set.")
            return
        end
        if not BagWardenData.itemSets[setName] then
            print("BagWarden: Set not found: " .. setName)
            return
        end
        StaticPopup_Show("BAGWARDEN_DELETE_SET", setName, nil, setName)
    elseif cmd == "list" then
        print("BagWarden sets:")
        for _, name in ipairs(sortedSetNames()) do
            local marker = (name == BagWardenData.currentSet) and "*" or "-"
            print(string.format(" %s %s", marker, name))
        end
    elseif cmd == "reset" then
        BagWardenData = DeepCopy(DefaultData)
        print("BagWarden: Reset to default configuration.")
        RefreshUI()
    elseif cmd == "help" then
        print("BagWarden commands:")
        print("/bw or /bgw: Toggle the tracker window.")
        print("/bw add <item name> [min count]: Track an item in the current set (min count optional).")
        print("/bw remove <item name>: Remove an item from the current set.")
        print("/bw load <set name>: Switch to another set.")
        print("/bw createset: Create a new set (also available via the UI).")
        print("/bw deleteset [set name]: Delete a set (defaults to the current set).")
        print("/bw list: Show saved sets.")
        print("/bw reset: Restore default sets.")
        print("/bw help: Show this help text.")
    else
        toggleFrame()
    end
end
