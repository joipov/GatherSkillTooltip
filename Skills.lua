local _, ns = ...

-- Cached profession ranks for the three gathering skills.

local GetProfessions = GetProfessions
local GetProfessionInfo = GetProfessionInfo

ns.skills = {
	herb = nil,
	mine = nil,
	skin = nil,
	herbBase = nil,
	mineBase = nil,
	skinBase = nil,
	herbMax = nil,
	mineMax = nil,
	skinMax = nil,
}

local refreshed = false

local function CacheProfession(index)
	if not index then
		return
	end
	local _, _, skillLevel, maxSkillLevel, _, _, skillLine, skillModifier = GetProfessionInfo(index)
	local rank = (skillLevel or 0) + (skillModifier or 0)
	local base = skillLevel or 0
	local maxSkill = maxSkillLevel or 0
	local skills = ns.skills
	if skillLine == ns.HERB_SKILL_LINE then
		skills.herb, skills.herbBase, skills.herbMax = rank, base, maxSkill
	elseif skillLine == ns.MINE_SKILL_LINE then
		skills.mine, skills.mineBase, skills.mineMax = rank, base, maxSkill
	elseif skillLine == ns.SKIN_SKILL_LINE then
		skills.skin, skills.skinBase, skills.skinMax = rank, base, maxSkill
	end
end

function ns.RefreshSkills()
	local skills = ns.skills
	skills.herb, skills.mine, skills.skin = nil, nil, nil
	skills.herbBase, skills.mineBase, skills.skinBase = nil, nil, nil
	skills.herbMax, skills.mineMax, skills.skinMax = nil, nil, nil
	refreshed = true
	local prof1, prof2 = GetProfessions()
	CacheProfession(prof1)
	CacheProfession(prof2)
end

-- Refreshes once if no refresh has happened yet this session.
function ns.EnsureSkills()
	if not refreshed then
		ns.RefreshSkills()
	end
end
