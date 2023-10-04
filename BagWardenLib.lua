dataobj = dataobj or {}


function dataobj:OnTooltipShow()
    self:AddLine("BagWarden")
    self:AddLine("Click to toggle BagWarden frame.", 0.2, 1, 0.2, 1)
end


function DeepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end