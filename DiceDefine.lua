local D6Define = {}

local Action = require("necro.game.system.Action")
local Attack = require("necro.game.character.Attack")
local Collision = require("necro.game.tile.Collision")
local CommonSpell = require("necro.game.data.spell.CommonSpell")
local Components = require("necro.game.data.Components")
local CustomEntities = require("necro.game.data.CustomEntities")
local Damage = require("necro.game.system.Damage")
local GFX = require("system.gfx.GFX")
local ItemBan = require("necro.game.item.ItemBan")
local ItemSlot = require("necro.game.item.ItemSlot")
local Move = require("necro.game.system.Move")
local Utilities = require("system.utils.Utilities")

D6Define.FormChangeMap = {
	{ 14, 8, 10, 17 },
	{ 6, 12, 18, 13 },
	{ 19, 16, 7, 9 },
	{ 11, 20, 15, 5 },
	{ 9, 4, 13, 21 },
	{ 22, 11, 2, 14 },
	{ 3, 15, 23, 10 },
	{ 16, 24, 12, 1 },
	{ 17, 3, 5, 22 },
	{ 1, 7, 21, 18 },
	{ 24, 19, 4, 6 },
	{ 8, 23, 20, 2 },
	{ 5, 2, 17, 23 },
	{ 21, 6, 1, 19 },
	{ 4, 18, 24, 7 },
	{ 20, 22, 8, 3 },
	{ 13, 1, 9, 24 },
	{ 2, 10, 22, 15 },
	{ 23, 14, 3, 11 },
	{ 12, 21, 16, 4 },
	{ 10, 5, 14, 20 },
	{ 18, 9, 6, 16 },
	{ 7, 13, 19, 12 },
	{ 15, 17, 11, 8 },
}

local D6_inventoryApplyEquipDice_slots = {
	ItemSlot.Type.SHOVEL,
	ItemSlot.Type.TORCH,
	ItemSlot.Type.WEAPON,
}
local D6_diceMinimumSlotCapacity_map = {
	[ItemSlot.Type.SHOVEL] = 100,
	[ItemSlot.Type.TORCH] = 100,
	[ItemSlot.Type.WEAPON] = 100,
}
local D6_purchasePriceMultiplier_map = {
	[ItemSlot.Type.SHOVEL] = 0.375,
	[ItemSlot.Type.TORCH] = 0.25,
	[ItemSlot.Type.WEAPON] = 0.5,
}
local D6_equipDiceSprite_texRectMap = {
	{ 0, 0, 12, 12 },
	{ 12, 0, 12, 12 },
	{ 24, 0, 12, 12 },
	{ 36, 0, 12, 12 },
	{ 48, 0, 12, 12 },
	{ 60, 0, 12, 12 },
}
local D6_spellcastRollSpell_spellTypes = {
	"SpellcastHeal",
	"SpellcastFreeze",
	"SpellcastFireball",
	"SpellcastMagicBomb",
	"SpellcastPulse",
	"SpellcastEarth",
}
local D6_spellcastRollSpell_directions = {
	[5] = Action.Direction.NONE,
	[6] = Action.Direction.NONE,
}
Components.register({
	D6_dice = {
		Components.constant.enum("excludedMoveFlags", Move.Flag, Move.Flag.mask(Move.Flag.TELEFRAG)),
		Components.field.int("form", 1),
		Components.field.int("point", 1),
		Components.constant.enum("requiredMoveFlags", Move.Flag, Move.Flag.mask(Move.Flag.CONTINUOUS, Move.Flag.TWEEN)),
		Components.dependency("hasMoved"),
		Components.dependency("tween"),
	},
	D6_dicePointDamage = {
		Components.constant.enum(
			"damageFlags",
			Damage.Flag,
			Damage.Flag.mask(Damage.Flag.BYPASS_ARMOR, Damage.Flag.BYPASS_IMMUNITY, Damage.Flag.BYPASS_INVINCIBILITY)
		),
		Components.constant.enum("damageFlagsRequired", Damage.Flag, Damage.Flag.PARRYABLE),
		Components.constant.int("heal", 0),
		Components.constant.int("invincibility", 1),
		Components.constant.enum(
			"moveType",
			Move.Flag,
			Move.Flag.mask(Move.Type.TELEPORT, Move.Flag.CONTINUOUS, Move.Flag.TELEFRAG)
		),
		Components.dependency("D6_dice"),
	},
	D6_dicePointDamageParticleSound = {
		Components.constant.string("sound", "shrineSacrifice"),
		Components.constant.table("soundData", { pitch = 1.125 }),
		Components.constant.string("texture", "ext/particles/TEMP_particle_blood.png"),
		Components.constant.int("particleCount", 28),
		Components.constant.float("duration", 1.75),
		Components.constant.float("maxDelay", 0.75),
		Components.constant.float("fadeDelay", 0.25),
		Components.constant.float("fadeTime", 0.75),
		Components.constant.float("minOpacity", 0.6),
		Components.constant.float("radius", 12),
		Components.constant.float("zVelocity", 75),
		Components.constant.float("gravity", -1.8),
		Components.constant.float("size", 1.5),
	},
	D6_dicePointDamageSpellCooldownDice = {
		Components.constant.float("multiplier", 1),
	},
	--- Shield victim that `health.health` or `health.maxHealth` equals to `D6_dice.point` when taking damage.
	D6_dicePointDefense = {
		Components.field.bool("previousValue"),
		Components.constant.enum("bypassDamageFlags", Damage.Flag, Damage.Flag.BYPASS_INVINCIBILITY),
		Components.constant.int("knockback", -1),
		Components.dependency("health"),
	},
	D6_diceFaceSprite = {
		Components.constant.string("texture", "mods/D6/dice_point.png"),
		Components.constant.table("texRectMap", D6_equipDiceSprite_texRectMap),
	},
	D6_diceMinimumSlotCapacity = {
		Components.constant.table("map", D6_diceMinimumSlotCapacity_map),
	},
	D6_dicePreview = {
		Components.constant.float("faceOffsetY", -4),
		Components.constant.string("pointDamageTexture", "mods/D6/dice_attack.png"),
		Components.constant.string("pointDefenseTexture", "mods/D6/dice_shield.png"),
		Components.dependency("gameObject"),
		Components.dependency("position"),
		Components.dependency("shadowPosition"),
		Components.dependency("sprite"),
	},
	D6_diceRandomFormOnSpawn = {
		Components.dependency("D6_dice"),
	},
	D6_diceSpriteSheet = {
		Components.field.int("previousForm"),
		Components.constant.table("formRemap"),
		Components.dependency("D6_dice"),
		Components.dependency("spriteSheet"),
	},
	D6_diceInnateAttack = {
		Components.field.bool("anySuccess"),
		Components.constant.enum("attackFlags", Attack.Flag, Attack.Flag.DIRECT),
		Components.constant.enum("damageType", Damage.Flag, Damage.Flag.PARRYABLE),
		Components.constant.int("failDamage", 1),
		Components.constant.enum(
			"failDamageType",
			Damage.Flag,
			Damage.Flag.mask(Damage.Flag.BYPASS_ARMOR, Damage.Flag.BYPASS_INVINCIBILITY)
		),
		Components.field.bool("hasAttacked"),
		Components.constant.localizedString("hint", "roll a %s"),
		Components.field.int("hintPoint"),
		Components.constant.int("knockback", 1),
		Components.constant.string("swipe", "enemy"),
		Components.dependency("D6_dicePointDamage"),
		Components.dependency("collisionCheckOnAttack"),
	},
	D6_diceOverridePlayerListSprite = {
		Components.constant.string("texture", "mods/D6/dice_head_hud.png"),
		Components.dependency("D6_dice"),
	},
	D6_dynamicItemCopySpriteFrames = {
		Components.dependency("DynChar_dynamicItem"),
		Components.dependency("spriteSheet"),
	},
	D6_equipDice = {
		Components.field.int("value"),
		Components.dependency("itemSlot"),
	},
	D6_equipDiceHint = {
		Components.constant.float("offsetY", 6),
		Components.constant.float("offsetYOnSale", 14),
		Components.dependency("D6_equipDice"),
		Components.dependency("position"),
		Components.dependency("visibility"),
	},
	D6_equipDiceOverrideOnDicePickup = {
		Components.dependency("D6_equipDice"),
	},
	D6_equipDiceRandomOnSpawn = {
		Components.dependency("D6_equipDice"),
	},
	D6_equipDiceSprite = {
		Components.dependency("D6_equipDice"),
	},
	--- Note: this will also override draw enemy hearts option.
	D6_everyoneRhythmIgnored = {},
	D6_healthHitDice = {
		Components.constant.int("point"),
	},
	D6_itemBanDice = {},
	D6_itemBanDiceOverpowered = {},
	D6_itemSpriteFrameXUseHolderDice = {
		Components.dependency("item"),
		Components.dependency("spriteSheet"),
	},
	D6_innateDiceScatterAction = {
		Components.constant.enum("action", Action.Special, Action.Special.ITEM_2),
		Components.constant.string("virtualEntityType", "D6_VirtualItemDiceScatter"),
	},
	D6_inventoryApplyEquipDice = {
		Components.constant.table("slots", D6_inventoryApplyEquipDice_slots),
		Components.dependency("D6_dice"),
	},
	D6_purchasePriceMultiplier = {
		Components.constant.table("map", D6_purchasePriceMultiplier_map),
	},
	D6_spellCooldownDice = {
		Components.field.int("remainingPoints"),
		Components.constant.int("cooldown", 6),
		Components.constant.localizedString("name", "point"),
		Components.constant.localizedString("pluralName", "points"),
	},
	D6_spellcastRollSpell = {
		Components.constant.table("directions", D6_spellcastRollSpell_directions),
		Components.constant.table("spellTypes", D6_spellcastRollSpell_spellTypes),
	},
	D6_virtualItemDiceScatter = {
		Components.constant.enum("mask", Collision.Type, Collision.Group.ITEM_PLACEMENT),
		Components.constant.string("sound", "trapScatter"),
	},
})

--- @diagnostic disable: missing-fields

CustomEntities.extend({
	name = "D6_Dice",
	template = CustomEntities.template.player(),
	components = {
		{
			D6_dice = {},
			D6_dicePointDamage = {},
			D6_dicePointDamageSpellCooldownDice = {},
			D6_dicePointDamageParticleSound = {},
			D6_dicePointDefense = {},
			D6_diceFaceSprite = {},
			D6_diceInnateAttack = {},
			D6_diceMinimumSlotCapacity = {},
			D6_dicePreview = {},
			D6_diceRandomFormOnSpawn = {},
			D6_diceSpriteSheet = {},
			D6_innateDiceScatterAction = {},
			D6_inventoryApplyEquipDice = {},
			D6_purchasePriceMultiplier = {},

			bestiary = { image = "mods/D6/bestiary.png", focusX = 220, focusY = 280 },
			bounceTweenOnAttack = {},
			friendlyName = { name = "Dice" },
			grooveChainFailImmunity = {},
			health = { health = 4, maxHealth = 6 },
			particleTakeDamage = {
				bounciness = 0.7,
				duration = 3.4,
				fadeTime = 2.5,
				gravity = 750,
				offsetZ = 12,
				texture = "mods/D6/dice_particle.png",
				velocity = 57,
			},
			sprite = { texture = "mods/D6/armor_body.png" },
			initialInventory = {
				items = {
					"WeaponDagger",
					"WeaponDagger",
					"ShovelBasic",
					"ShovelBasic",
					"Bomb",
					"Torch1",
					"D6_SpellRollMagic",
				},
			},
			inventoryBannedItems = {
				components = {
					D6_itemBanDice = ItemBan.Type.FULL,
					--- We don't fully ban this item, because its really fun.
					D6_itemBanDiceOverpowered = ItemBan.Type.GENERATION_ALL,

					itemBanInnateSpell = ItemBan.Type.LOCK,
				},
			},
			playableCharacter = { lobbyOrder = 6 },
			textCharacterSelectionMessage = {
				text = "Dice Mode:\nUnleash the power of the D6.\nWith unlimited item slots!",
			},
			traitInnatePeace = {},
			wiredAnimation = { frames = { 72, 24, 48 } },

			facingMirrorX = false,
			hudPlayerListUseAttachmentSprite = false,
			normalAnimation = false,
			voiceConfused = false,
			voiceDeath = false,
			voiceDescend = false,
			voiceDig = false,
			voiceGrabbed = false,
			voiceGreeting = false,
			voiceHeal = false,
			voiceHit = false,
			voiceHotTileStep = false,
			voiceMeleeAttack = false,
			voiceNotice = false,
			voiceRangedAttack = false,
			voiceShrink = false,
			voiceSlideStart = false,
			voiceSpellCasterPrefix = false,
			voiceSquish = false,
			voiceStairsUnlock = false,
			voiceTeleport = false,
			voiceUnshrink = false,
			voiceWind = false,
		},
		{
			sprite = { texture = "mods/D6/head.png" },
		},
	},
})

CustomEntities.extend({
	name = "D6_SpellRollMagic",
	template = CustomEntities.template.item("spell_transform"),
	components = {
		D6_dynamicItemCopySpriteFrames = {},
		D6_itemSpriteFrameXUseHolderDice = {},
		D6_spellCooldownDice = {},

		DynChar_dynamicItem = { texture = "mods/D6/spell_roll_magic_dyn.png", width = 14, height = 12 },

		friendlyName = { name = "Dice Spell" },
		itemCastOnUse = { spell = "D6_SpellcastRollSpell" },
		itemHintLabel = { text = "Casting determined\nby dice rolls" },
		itemSlot = { name = ItemSlot.Type.SPELL },
		spellBloodMagic = { damage = 3, killerName = "Blood Magic (Dice)" },
		spellReusable = {},
		sprite = { texture = "mods/D6/spell_roll_magic.png", width = 24, height = 24 },
	},
})

CustomEntities.register({
	name = "D6_DiceLoreMarker",

	D6_everyoneRhythmIgnored = {},

	gameObject = {},
	position = {},
})

CustomEntities.register({
	name = "D6_VirtualItemDiceScatter",

	D6_virtualItemDiceScatter = {},

	friendlyName = { name = "Scatter" },
	sprite = { texture = "mods/D6/dice_scatter.png" },
})

for i = 1, 6 do
	local texture = "mods/D6/dice_point.png"
	local size = GFX.getImageHeight(texture)

	CustomEntities.register({
		name = "D6_" .. i,

		sprite = { texture = texture, textureShiftX = (i - 1) * size, width = size, height = size },
	})
end

--- @diagnostic enable: missing-fields

CommonSpell.registerSpell("D6_SpellcastRollSpell", {
	D6_spellcastRollSpell = {},

	spellcastUseFacingDirection = {},
	spellcastUpgradable = { upgradeTypes = { greater = "D6_SpellcastRollSpellGreater" } },
})

CommonSpell.registerSpell("D6_SpellcastRollSpellGreater", {
	D6_spellcastRollSpell = {
		spellTypes = (function(map)
			map = Utilities.fastCopy(map)
			for k, v in pairs(map) do
				map[k] = tostring(v) .. "Greater"
			end
			return map
		end)(D6_spellcastRollSpell_spellTypes),
	},

	spellcastUseFacingDirection = {},
})

event.entitySchemaLoadEntity.add("healthHitDice", "overrides", function(ev)
	local healthHitDice

	if ev.entity.multiTile then
		healthHitDice = {}
	elseif ev.entity.crateLike then
		healthHitDice = { point = 3 }
	elseif ev.entity.boss or ev.entity.playableCharacter or ev.entity.playableCharacterDLC or ev.entity.shopkeeper then
		if ev.entity.luteHead or ev.entity.necrodancer then
			healthHitDice = {}
		else
			healthHitDice = { point = 6 }
		end
	elseif ev.entity.enemy then
		if
			ev.entity.shield
			and ev.entity.shield.bypassDamage
			and ev.entity.shield.bypassDamage >= 1
			and ev.entity.shield.bypassDamage <= 6
		then
			healthHitDice = { point = ev.entity.shield.bypassDamage }
		end
	elseif ev.entity.attackable then
		if ev.entity.ai then
			healthHitDice = { point = 5 }
		else
			healthHitDice = { point = 4 }
		end
	end

	if healthHitDice then
		ev.entity.D6_healthHitDice = healthHitDice
		-- ev.entity.D6_healthHitDiceHint = {}
	end
end)

for name, point in pairs({
	ShopkeeperGhost = 1,
}) do
	event.entitySchemaLoadNamedEntity.add("healthHitDice" .. name, name, function(ev)
		ev.entity.D6_healthHitDice = { point = point }
	end)
end

event.entitySchemaLoadEntity.add("itemBanDiceCharacter", "overrides", function(ev)
	if ev.entity.itemCapacityModifier or ev.entity.itemHolster or ev.entity.itemBag then
		ev.entity.D6_itemBanDice = {}
	elseif ev.entity.itemForceSlidingTween then
		ev.entity.D6_itemBanDiceOverpowered = {}
	end
end)

event.entitySchemaLoadEntity.add("itemEquipDice", "overrides", function(ev)
	if ev.entity.itemCommon and ev.entity.itemSlot then
		ev.entity.D6_equipDice = {}
		ev.entity.D6_equipDiceOverrideOnDicePickup = {}
		ev.entity.D6_equipDiceSprite = {}

		if ev.entity.itemInitial then
			ev.entity.D6_equipDiceRandomOnSpawn = {}
		end
	end
end)

for _, name in ipairs({ "WeaponGoldenLute" }) do
	event.entitySchemaLoadNamedEntity.add("itemEquipDiceExclude" .. name, name, function(ev)
		ev.entity.D6_equipDice = false
		ev.entity.D6_equipDiceOverrideOnDicePickup = false
		ev.entity.D6_equipDiceSprite = false
		ev.entity.D6_equipDiceRandomOnSpawn = false
	end)
end

return D6Define
