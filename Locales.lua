local _, ns = ...

-- Locale-dependent lookups that need the final ns.L (Locales/enUS.lua plus
-- the client-locale overlay), and client-provided names.

local C_Spell = C_Spell
local C_TradeSkillUI = C_TradeSkillUI

-- Localized creature type names; fallback for ns.SKIN_TYPE_IDS (Data.lua).
ns.SKIN_TYPES = {
	Beast = true,
	Dragonkin = true,
	[ns.L.CREATURE_BEAST] = true,
	[ns.L.CREATURE_DRAGONKIN] = true,
}

-- The client's own "Skinnable" tooltip string when available.
-- the localized table entry is the fallback.
ns.SKINNABLE_TEXT = _G.UNIT_SKINNABLE_LEATHER or ns.L.SKINNABLE

function ns.SpellName(spellID, fallback)
	local name = C_Spell.GetSpellName(spellID)
	if name and name ~= "" then
		return name
	end
	return fallback
end

function ns.ProfessionName(skillLine, fallback)
	local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
	if type(info) == "table" and info.professionName and info.professionName ~= "" then
		return info.professionName
	end
	return fallback
end

function ns.ExampleHerb()
	return ns.L.EXAMPLE_HERB or "Peacebloom"
end
