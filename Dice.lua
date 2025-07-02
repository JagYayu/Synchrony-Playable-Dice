local D6 = {}
local D6Define = require("D6.DiceDefine")

local Action = require("necro.game.system.Action")
local ActionItem = require("necro.game.item.ActionItem")
local AnimationTimer = require("necro.render.AnimationTimer")
local Attack = require("necro.game.character.Attack")
local Collision = require("necro.game.tile.Collision")
local CurrentLevel = require("necro.game.level.CurrentLevel")
local Damage = require("necro.game.system.Damage")
local ECS = require("system.game.Entities")
local Flyaway = require("necro.game.system.Flyaway")
local GameSession = require("necro.client.GameSession")
local Health = require("necro.game.character.Health")
local Inventory = require("necro.game.item.Inventory")
local Invincibility = require("necro.game.character.Invincibility")
local Move = require("necro.game.system.Move")
local Object = require("necro.game.object.Object")
local ObjectMap = require("necro.game.object.Map")
local Random = require("system.utils.Random")
local RhythmMode = require("necro.game.data.modifier.RhythmMode")
local Particle = require("necro.game.system.Particle")
local RNG = require("necro.game.system.RNG")
local Settings = require("necro.config.Settings")
local SettingsStorage = require("necro.config.SettingsStorage")
local Snapshot = require("necro.game.system.Snapshot")
local Sound = require("necro.audio.Sound")
local Spell = require("necro.game.spell.Spell")
local Swipe = require("necro.game.system.Swipe")
local TextPool = require("necro.config.i18n.TextPool")
local Tile = require("necro.game.tile.Tile")
local Turn = require("necro.cycles.Turn")
local Utilities = require("system.utils.Utilities")

local ceil = math.ceil
local clamp = Utilities.clamp
local floor = math.floor
local tonumber = tonumber

--- Get point at top of dice.
--- @param form integer
--- @return integer
function D6.getPoint(form)
	return floor((form - 1) / 4) + 1
end

--- @param dice Component.D6_dice
--- @param form integer
function D6.setForm(dice, form)
	dice.form = form
	dice.point = D6.getPoint(form)
end

--- @param direction Action.Direction
--- @return integer
function D6.directionToFormChangeIndex(direction)
	return ceil(direction * 0.5)
end

--- Get the form after dice rolled at specific direction.
--- @param form integer
--- @param direction Action.Direction
--- @return integer?
function D6.nextForm(form, direction)
	local map = D6Define.FormChangeMap[form]
	if type(map) == "table" then
		return tonumber(map[D6.directionToFormChangeIndex(direction)])
	end
end

event.objectMove.add("diceChangeForm", {
	filter = "D6_dice",
	order = "hasMoved",
	sequence = 6,
}, function(ev)
	if ev.entity.hasMoved.value and ev.entity.tween.maxHeight ~= 0 then
		local direction = Action.move(ev.x - ev.prevX, ev.y - ev.prevY)
		local dice = ev.entity.D6_dice

		if
			Action.isOrthogonalDirection(direction)
			and Move.Flag.check(ev.moveType, dice.requiredMoveFlags)
			and not Move.Flag.check(ev.moveType, dice.excludedMoveFlags)
		then
			local form = D6.nextForm(dice.form, direction)
			if form and form ~= dice.form then
				ev.D6_roll = dice.form
				D6.setForm(dice, form)
			end
		end
	end
end)

event.turn.add("resetDiceSpriteSheetPreviousForm", "resetAnimations", function()
	for entity in ECS.entitiesWithComponents({ "D6_diceSpriteSheet" }) do
		entity.D6_diceSpriteSheet.previousForm = entity.D6_dice.form
	end
end)

event.animateObjects.add("applyDiceSpriteSheet", "normal", function()
	for entity in ECS.entitiesWithComponents({ "D6_diceSpriteSheet" }) do
		local form = AnimationTimer.getFactor(entity.id, "tween", entity.tween.duration) < 0.5
				and entity.D6_diceSpriteSheet.previousForm
			or entity.D6_dice.form
		entity.spriteSheet.frameX = tonumber(entity.D6_diceSpriteSheet.formRemap[form]) or form
	end
end)

event.inventorySlotCapacity.add("diceMinimumSlotCapacity", { sequence = 6 }, function(ev)
	if ev.holder.D6_diceMinimumSlotCapacity then
		local value = ev.holder.D6_diceMinimumSlotCapacity.map[ev.slot]
		if value then
			ev.capacity = math.max(value, ev.capacity)
		end
	end
end)

event.frame.add("inventoryApplyEquipDice", "actability", function(ev)
	for entity in ECS.entitiesWithComponents({ "D6_inventoryApplyEquipDice" }) do
		local point = entity.D6_dice.point

		for _, slot in ipairs(entity.D6_inventoryApplyEquipDice.slots) do
			for _, item in ipairs(Inventory.getItemsInSlot(entity, slot)) do
				if item.D6_equipDice then
					if item.D6_equipDice.value == point then
						Inventory.equip(item, entity)
					else
						Inventory.unequip(item, entity)
					end
				end
			end
		end
	end
end)

local componentNames_itemSlot_sale = { "itemSlot", "sale" }

event.objectCheckPurchase.add("applyPurchasePriceMultiplier", {
	filter = "D6_purchasePriceMultiplier",
	order = "multiplier",
}, function(ev)
	if not ev.price then
		return
	end

	local slot

	local id = ev.price.id
	for entity in ECS.entitiesWithComponents(componentNames_itemSlot_sale) do
		if entity.sale.priceTag == id then
			slot = entity.itemSlot.name
			break
		end
	end

	if slot then
		ev.multiplier = ev.multiplier * (tonumber(ev.entity.D6_purchasePriceMultiplier.map[slot]) or 1)
	end
end)

D6.RNG_Channel = RNG.Channel.extend("D6_Channel")

event.objectSpawn.add("diceRandomForm", {
	filter = "D6_diceRandomFormOnSpawn",
	order = "overrides",
}, function(ev)
	D6.setForm(ev.entity.D6_dice, RNG.int(#D6Define.FormChangeMap, D6.RNG_Channel) + 1)
end)

event.objectSpawn.add("luckyPointRandom", {
	filter = "D6_equipDiceRandomOnSpawn",
	order = "overrides",
}, function(ev)
	ev.entity.D6_equipDice.value = RNG.range(1, 6, D6.RNG_Channel)
end)

event.inventoryAddItem.add("luckyPointOverrideOnDicePickup", {
	filter = "D6_equipDiceOverrideOnDicePickup",
	order = "equip",
}, function(ev)
	if
		ev.holder.D6_dice
		and not CurrentLevel.isLoading()
		and (not ev.holder.beatCounter or ev.holder.beatCounter.counter > 0)
	then
		ev.item.D6_equipDice.value = ev.holder.D6_dice.point
	end
end)

event.turn.add("resetDiceInnateAttackFields", {
	order = "activation",
	sequence = 6,
}, function()
	-- for entity in ECS.entitiesWithComponents({ "D6_diceInnateAttack" }) do
	-- 	if entity.gameObject.active then
	-- 		entity.D6_diceInnateAttack.hasAttacked = false
	-- 	end
	-- end
end)

event.objectDirection.add("resetDiceInnateAttackFields", {
	filter = "D6_diceInnateAttack",
	order = "hasMoved",
}, function(ev)
	ev.entity.D6_diceInnateAttack.hasAttacked = false
end)

event.objectCheckMove.add("checkDiceInnateAttack", {
	filter = "D6_diceInnateAttack",
	order = "attackCheck",
}, function(ev) --- @param ev Event.ObjectCheckMove
	if
		ev.result == nil
		and not ev.entity.D6_diceInnateAttack.hasAttacked
		and (not ev.entity.previousPosition or (ev.prevX == ev.entity.previousPosition.x and ev.prevY == ev.entity.previousPosition.y))
		and Move.Flag.check(ev.moveType, Move.Flag.HANDLE_ATTACK)
	then
		local x = ev.x
		local y = ev.y
		if Move.Flag.check(ev.moveType, Move.Flag.COLLIDE_INTERMEDIATE) then
			x = ev.prevX + Utilities.sign(ev.x - ev.prevX)
			y = ev.prevY + Utilities.sign(ev.y - ev.prevY)
		end

		if not Collision.check(x, y, ev.entity.collisionCheckOnAttack.mask) then
			local targets =
				Attack.getAttackableEntitiesOnTile(ev.entity, x, y, ev.entity.D6_diceInnateAttack.attackFlags)
			if targets[1] then
				ev.result = Action.Result.ATTACK
				ev.targets = targets
				ev.x = x
				ev.y = y
			end
		end
	end
end)

event.objectCheckMove.add("performDiceInnateAttack", {
	filter = "D6_diceInnateAttack",
	order = "attack",
}, function(ev) --- @param ev Event.ObjectCheckMove
	if ev.targets and not ev.entity.D6_diceInnateAttack.hasAttacked and ev.result == Action.Result.ATTACK then
		local attacker = ev.entity

		local dx = ev.x - attacker.position.x
		local dy = ev.y - attacker.position.y
		local direction = Action.move(dx, dy)

		Swipe.create({
			attacker = attacker,
			type = attacker.D6_diceInnateAttack.swipe,
			x = ev.x,
			y = ev.y,
			dx = dx,
			dy = dy,
			direction = direction,
		})

		local anySuccess = false
		local innateAttack = attacker.D6_diceInnateAttack

		innateAttack.hasAttacked = true
		innateAttack.anySuccess = false
		innateAttack.hintPoint = -1

		for _, victim in ipairs(ev.targets) do
			anySuccess = Damage.inflict({
				attacker = attacker,
				victim = victim,
				direction = direction,
				damage = 0,
				type = innateAttack.damageType,
				knockback = innateAttack.knockback,
			}) or anySuccess
		end

		if
			anySuccess
			and not innateAttack.anySuccess
			and Damage.inflict({
				attacker = ev.targets[1],
				victim = attacker,
				direction = Action.rotateDirection(direction, Action.Rotation.MIRROR),
				damage = innateAttack.failDamage,
				type = innateAttack.failDamageType,
			})
			and innateAttack.hintPoint ~= -1
		then
			Flyaway.createIfFocused({
				entity = attacker,
				text = innateAttack.hint:format(innateAttack.hintPoint),
				alignY = 0,
			})
		end
	end
end)

event.objectDealDamage.add("postCheckDiceInnateAttack", {
	filter = "D6_diceInnateAttack",
	order = "additionalEffects",
	sequence = 6.6,
}, function(ev) --- @param ev Event.ObjectDealDamage
	if ev.D6_critical then
		ev.entity.D6_diceInnateAttack.anySuccess = true
	elseif ev.entity.D6_diceInnateAttack.hintPoint == -1 then
		ev.entity.D6_diceInnateAttack.hintPoint = D6.getHealthDice(ev.victim) or ev.entity.D6_diceInnateAttack.hintPoint
	end
end)

function D6.getHealthDice(entity)
	if entity.D6_healthHitDice then
		local dice = entity.D6_healthHitDice.point
		if dice >= 1 and dice <= 6 then
			return dice
		end
	elseif entity.health then
		return clamp(1, entity.health.health, 6)
	end
end

--- @deprecated
function D6.checkHealthDice(dicePoint, victim)
	error("`D6.checkHealthDice` is depreciated", 2)
	return dicePoint == D6.getHealthDice(victim)
end

event.objectDealDamage.add("dicePointDamage", {
	filter = "D6_dicePointDamage",
	order = "applyDamage",
	sequence = -6,
}, function(ev)
	if not ev.suppressed and ev.attacker.id ~= ev.victim.id then
		local dice = D6.getHealthDice(ev.victim)
		if
			dice == ev.entity.D6_dice.point
			and Damage.Flag.check(ev.type, ev.entity.D6_dicePointDamage.damageFlagsRequired)
			and Utilities.distanceL1(
					ev.entity.position.x - ev.victim.position.x,
					ev.entity.position.y - ev.victim.position.y
				)
				== 1
		then
			ev.D6_critical = {
				point = dice,
				x = ev.victim.position.x,
				y = ev.victim.position.y,
			}
			ev.damage = ev.damage + ev.entity.D6_dice.point
			ev.type = Damage.Flag.mask(ev.type, ev.entity.D6_dicePointDamage.damageFlags)
		end
	end
end)

event.objectDealDamage.add("dicePointDamageTelefreg", {
	filter = "D6_dicePointDamage",
	order = "additionalEffects",
	sequence = 6,
}, function(ev)
	if ev.D6_critical and not ev.suppressed and ev.damage > 0 then
		Invincibility.activate(ev.entity, ev.entity.D6_dicePointDamage.invincibility)

		if ev.D6_critical.point * 2 > ev.entity.health.health then
			Health.heal({
				D6_victim = ev.victim,
				entity = ev.entity,
				healer = ev.entity,
				health = ev.entity.D6_dicePointDamage.heal,
				allowOverheal = false,
				noParticles = true,
			})
		end

		if not ev.survived and not ev.entity.hasMoved.value then
			Move.absolute(ev.entity, ev.D6_critical.x, ev.D6_critical.y, ev.entity.D6_dicePointDamage.moveType)
			ev.entity.hasMoved.value = true
		end
	end
end)

event.objectDealDamage.add("dicePointDamageParticleSound", {
	filter = "D6_dicePointDamageParticleSound",
	order = "additionalEffects",
	sequence = 6.6,
}, function(ev)
	if ev.D6_critical and not ev.suppressed then
		Sound.playFromEntity(
			ev.entity.D6_dicePointDamageParticleSound.sound,
			ev.entity,
			Utilities.fastCopy(ev.entity.D6_dicePointDamageParticleSound.soundData)
		)

		if ev.victim.sprite then
			Particle.play(ev.entity, "D6_dicePointDamageParticleSound", {
				type = "dicePointDamageParticle",
				texture = ev.victim.sprite.texture,
				width = ev.victim.sprite.width,
				height = ev.victim.sprite.height,
			})
		end
	end
end)

event.objectDealDamage.add("dicePointDamageReduceSpellCooldownDice", {
	filter = "D6_dicePointDamageSpellCooldownDice",
	order = "damageCountdown",
	sequence = 6,
}, function(ev)
	if ev.D6_critical and not ev.suppressed then
		local point = ev.D6_critical.point * ev.entity.D6_dicePointDamageSpellCooldownDice.multiplier

		for _, item in ipairs(Inventory.getItems(ev.entity)) do
			if item.D6_spellCooldownDice then
				item.D6_spellCooldownDice.remainingPoints =
					math.max(0, item.D6_spellCooldownDice.remainingPoints - point)
			end
		end
	end
end)

--- @param entity Entity
--- @return boolean?
function D6.checkDefense(entity, point)
	if not (entity.D6_dice and entity.health) then
		return
	elseif entity.freezable and (entity.freezable.permanent or entity.freezable.remainingTurns > 0) then
		return false
	end

	point = point or entity.D6_dice.point
	return point >= 6 or entity.health.health == point
end

event.turn.add("updateDicePointDefense", "invincibility", function()
	for entity in ECS.entitiesWithComponents({ "D6_dicePointDefense" }) do
		entity.D6_dicePointDefense.previousValue = not not D6.checkDefense(entity)
	end
end)

event.objectTakeDamage.add("dicePointDefense", {
	filter = "D6_dicePointDefense",
	order = "invincibility",
	sequence = 6,
}, function(ev)
	if not Damage.Flag.check(ev.type, ev.entity.D6_dicePointDefense.bypassDamageFlags) then
		if ev.entity.D6_dicePointDefense.previousValue or D6.checkDefense(ev.entity) then
			ev.damage = 0
			ev.shielded = true

			local knockback = ev.entity.D6_dicePointDefense.knockback
			if knockback ~= -1 then
				ev.knockback = knockback

				if ev.suppressed and not ev.D6_retainSuppression then
					ev.suppressed = false
				end
			end
		end
	end
end)

event.objectGetActionItem.add("innateDiceScatterItem", {
	filter = "D6_innateDiceScatterAction",
	order = "slotItems",
	sequence = 6,
}, function(ev)
	if ev.item == nil and ev.action == ev.entity.D6_innateDiceScatterAction.action then
		ev.item = ECS.getEntityPrototype(ev.entity.D6_innateDiceScatterAction.virtualEntityType)
		ev.slotLabel = ev.item and ev.item.friendlyName and ev.item.friendlyName.name or ev.text
	end
end)

local function getDiceScatterOffsets(entity)
	if not entity.facingDirection then
		return false
	end

	local offsets = {
		{ 1, 0 },
		{ 0, -1 },
		{ 0, 1 },
		{ 1, -1 },
		{ 1, 1 },
		{ 2, 0 },
		{ 0, -2 },
		{ 0, 2 },
	}
	for _, t in ipairs(offsets) do
		t[1], t[2] = Action.rotate(t[1], t[2], entity.facingDirection.direction)
	end
	return offsets
end

event.objectSpecialAction.add("diceScatter", {
	filter = "D6_inventoryApplyEquipDice",
	order = "item",
	sequence = -6,
}, function(ev)
	if ev.result == nil then
		local virtualScatterItem = ActionItem.getActionItem(ev.entity, ev.action)
		local options = virtualScatterItem and virtualScatterItem.D6_virtualItemDiceScatter
		if options then
			local offsets = nil

			for _, item in ipairs(Inventory.getItems(ev.entity)) do
				if
					item.D6_equipDice
					and item.D6_equipDice.value == ev.entity.D6_dice.point
					and Utilities.arrayFind(ev.entity.D6_inventoryApplyEquipDice.slots, item.itemSlot.name)
				then
					Inventory.drop(item, ev.entity.position.x, ev.entity.position.y)
					offsets = offsets or getDiceScatterOffsets(ev.entity)
					Object.moveToNearbyVacantTile(item, options.mask, Move.Type.NORMAL, offsets)
				end
			end

			if offsets ~= nil then
				Sound.playFromEntity(options.sound, ev.entity)
			end
		end
	end
end)

event.spellInit.add("rollSpellCast", {
	filter = "D6_spellcastRollSpell",
	order = "chaincast",
	sequence = 6,
}, function(ev)
	local point
	if ev.caster.D6_dice then
		point = ev.caster.D6_dice.point
	elseif ev.caster.random then
		point = RNG.range(1, 6, ev.entity)
	else
		point = Random.noise3(Turn.getCurrentTurnID(), ev.caster.id, CurrentLevel.getSeed(), 5) + 1
	end

	local spellType = ev.entity.D6_spellcastRollSpell.spellTypes[point]
	if spellType then
		Spell.castAt(
			ev.caster,
			spellType,
			ev.x,
			ev.y,
			ev.entity.D6_spellcastRollSpell.directions[point] or ev.direction
		)
	end
end)

event.spellItemCooldown.add("spellCooldownDice", {
	filter = "D6_spellCooldownDice",
	order = "kills",
}, function(ev)
	local point = ev.entity.D6_spellCooldownDice.remainingPoints
	if point > 0 then
		ev.cooldowns[#ev.cooldowns + 1] = {
			name = ev.entity.D6_spellCooldownDice.name,
			pluralName = ev.entity.D6_spellCooldownDice.pluralName,
			amount = point,
		}
	end
end)

event.spellItemActivate.add("resetSpellDiceCooldown", {
	filter = "D6_spellCooldownDice",
	order = "killCooldown",
}, function(ev)
	ev.entity.D6_spellCooldownDice.remainingPoints = ev.entity.D6_spellCooldownDice.cooldown
end)

SettingLore = Settings.shared.bool({
	id = "lore",
	name = "Enable dice lore",
	default = true,
})

D6.LoreLabelKey = TextPool.register("Dice lore", "label.lobby.stair.codex.D6_diceLore")

local function trySpawnTrigger(x, y)
	local info = Tile.getInfo(x, y)
	local file = "mods/D6/dice_lore.necrolevel"

	if info and info.name == "LobbyStairs" then
		local entity = ObjectMap.firstWithComponent(x, y, "trapStartRun")
		if entity and entity.trapStartRun.fileName == file then
			return true
		end
	else
		Tile.setType(x, y, "LobbyStairs")

		for _, entry in ipairs({
			{
				name = "TriggerStartRun",
				attributes = {
					trapLoadMod = { modName = "D6" },
					trapStartRun = {
						mode = GameSession.Mode.CustomDungeon,
						fileName = file,
					},
				},
			},
			{
				name = "LabelLobby",
				attributes = { worldLabelTextPool = { key = D6.LoreLabelKey } },
			},
		}) do
			Object.spawn(entry.name, x, 5, entry.attributes)
		end

		return true
	end

	return false
end

local function spawnTrigger()
	if CurrentLevel.isLobby() and SettingLore then
		for i, x in ipairs({ 8, 14, 9, 13 }) do
			if trySpawnTrigger(x, 5) then
				return i
			end
		end
	end
end

event.contentLoad.add("loadDiceLore", "regenerateLobby", spawnTrigger)
event.gameStateLevel.add("loadDiceLore", "lobbyLevel", spawnTrigger)

DiceLoreRhythmNoBeat = Snapshot.variable(false)

event.gameStateLevel.add("diceLoreRhythmIgnore", "levelLoadingDone", function()
	if
		Object.firstWithComponents({ "D6_everyoneRhythmIgnored" })
		and RhythmMode.getMode() ~= RhythmMode.Type.NO_BEAT
	then
		--- Following code would cause lag spike somehow... I'll use another way
		-- for entity in ECS.entitiesWithComponents { "rhythmIgnoredTemporarily" } do
		-- 	entity.rhythmIgnoredTemporarily.endTime = math.huge
		-- 	entity.rhythmIgnoredTemporarily.active = true
		-- end

		SettingsStorage.set("gameplay.modifiers.rhythm", RhythmMode.Type.NO_BEAT, Settings.Layer.SCRIPT_OVERRIDE)
		SettingsStorage.set("video.alwaysShowEnemyHearts", true, Settings.Layer.SCRIPT_OVERRIDE)
		DiceLoreRhythmNoBeat = true
	end
end)

event.gameStateEnterLobby.add("diceLoreRhythmNoBeatReset", "sessionMods", function(ev)
	if DiceLoreRhythmNoBeat then
		DiceLoreRhythmNoBeat = false
		SettingsStorage.set("gameplay.modifiers.rhythm", nil, Settings.Layer.SCRIPT_OVERRIDE)
		SettingsStorage.set("video.alwaysShowEnemyHearts", nil, Settings.Layer.SCRIPT_OVERRIDE)
	end
end)

return D6
