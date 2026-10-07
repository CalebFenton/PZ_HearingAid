require "ISUI/ISToolTipInv"
require "HearingAid/HearingAid"

-- Draws battery and switch rows under the tooltip of working hearing aids. Java draws the vanilla
-- item tooltip, so the rows go in a strip drawn after ISToolTipInv.render.

local BAR_WIDTH = 80
local BAR_HEIGHT = 4
local PAD = 5

local function drawBar(panel, x, y, fraction)
    local done = math.floor(BAR_WIDTH * fraction)
    if fraction > 0 then
        done = math.max(done, 1)
    end
    panel:drawRect(x, y, done, BAR_HEIGHT, 1.0, 1.0 - fraction, fraction, 0.0)
    panel:drawRect(x + done, y, BAR_WIDTH - done, BAR_HEIGHT, 1.0, 0.25, 0.25, 0.25)
end

local function statusText(aid)
    if not HearingAid.isOn(aid) then
        return getText("IGUI_HearingAid_Off"), 0.7, 0.7, 0.7
    end
    if not aid:isWorn() then
        return getText("IGUI_HearingAid_OnNotWorn"), 1.0, 0.8, 0.4
    end
    return getText("IGUI_HearingAid_On"), 0.4, 1.0, 0.4
end

local vanillaRender = ISToolTipInv.render

function ISToolTipInv:render()
    vanillaRender(self)
    local aid = self.item
    -- Vanilla skips the tooltip while a context menu is open.
    if not HearingAid.isWorking(aid) or (ISContextMenu.instance and ISContextMenu.instance.visibleCheck) then
        return
    end

    local font = self.tooltip:getFont()
    local textManager = getTextManager()
    local lineHeight = textManager:getFontHeight(font)
    local label = getText("IGUI_HearingAid_Battery") .. ":"
    local barX = PAD + textManager:MeasureStringX(font, label) + PAD
    local width = math.max(self.width, barX + BAR_WIDTH + PAD + textManager:MeasureStringX(font, "100%") + PAD)
    local top = self.height
    local height = PAD + lineHeight * 2 + PAD
    -- Flip above the tooltip if the strip would leave the screen.
    if self:getAbsoluteY() + top + height > getCore():getScreenHeight() then
        top = -height
    end
    self:drawRect(0, top, width, height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
    self:drawRectBorder(0, top, width, height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    local y = top + PAD
    self:drawText(label, PAD, y, 1.0, 1.0, 0.8, 1.0, font)
    if HearingAid.hasBattery(aid) then
        local charge = HearingAid.getCharge(aid)
        drawBar(self, barX, y + (lineHeight - BAR_HEIGHT) / 2, charge)
        self:drawText(round(charge * 100) .. "%", barX + BAR_WIDTH + PAD, y, 1.0, 1.0, 1.0, 1.0, font)
    else
        self:drawText(getText("IGUI_HearingAid_NoBattery"), barX, y, 0.7, 0.7, 0.7, 1.0, font)
    end

    y = y + lineHeight
    local text, r, g, b = statusText(aid)
    self:drawText(text, PAD, y, r, g, b, 1.0, font)
end
