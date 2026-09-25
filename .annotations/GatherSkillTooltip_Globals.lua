---@meta

-- LuaLS declarations for Blizzard globals that the Ketho "WoW API"
-- Core annotations do not define (TOOL-002). Only what this addon uses.
-- Runtime source for each entry: Forever client build 70009 UI code
-- (Blizzard_SharedXML/Tooltip/TooltipDataHandler.lua, Blizzard_Settings*).

---@class TooltipDataProcessor
TooltipDataProcessor = {}

---@param dataType Enum.TooltipDataType
---@param callback fun(tooltip: GameTooltip, data: TooltipData?)
function TooltipDataProcessor.AddTooltipPostCall(dataType, callback) end

---@type { [string]: fun(msg: string, editBox: table?) }
SlashCmdList = {}

---@class SettingsCategory
local SettingsCategory = {}
---@return number
function SettingsCategory:GetID() end

---@class SettingsLayout
local SettingsLayout = {}
---@param initializer table
function SettingsLayout:AddInitializer(initializer) end

---@class AddOnSetting
local AddOnSetting = {}
---@return any
function AddOnSetting:GetValue() end
---@param callback fun(setting: AddOnSetting, value: any)
function AddOnSetting:SetValueChangedCallback(callback) end

---@class SettingsCheckboxInitializer
local SettingsCheckboxInitializer = {}
---@param parent SettingsCheckboxInitializer
---@param predicate fun(): boolean
function SettingsCheckboxInitializer:SetParentInitializer(parent, predicate) end

---@class Settings
---@field VarType { Boolean: "boolean", Number: "number", String: "string" }
Settings = {}

---@param name string
---@return SettingsCategory category
---@return SettingsLayout layout
function Settings.RegisterVerticalLayoutCategory(name) end

---@param category SettingsCategory
function Settings.RegisterAddOnCategory(category) end

---@param category SettingsCategory
---@param variable string
---@param variableKey string
---@param variableTbl table
---@param variableType string
---@param name string
---@param defaultValue any
---@return AddOnSetting
function Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue) end

---@param category SettingsCategory
---@param setting AddOnSetting
---@param tooltip string?
---@return SettingsCheckboxInitializer
function Settings.CreateCheckbox(category, setting, tooltip) end

---@param categoryID number
function Settings.OpenToCategory(categoryID) end

---@param name string
---@return table
function CreateSettingsListSectionHeaderInitializer(name) end
