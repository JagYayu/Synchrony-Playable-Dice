local D6 = require("D6.Dice")
local D6Visual = {}

local Action = require("necro.game.system.Action")
local AnimationTimer = require("necro.render.AnimationTimer")
local Attack = require("necro.game.character.Attack")
local Beatmap = require("necro.audio.Beatmap")
local Bitmap = require("system.game.Bitmap")
local Collision = require("necro.game.tile.Collision")
local Color = require("system.utils.Color")
local CommonFilter = require("necro.render.filter.CommonFilter")
local CurrentLevel = require("necro.game.level.CurrentLevel")
local ECS = require("system.game.Entities")
local Focus = require("necro.game.character.Focus")
local GFX = require("system.gfx.GFX")
local HUDLayout = require("necro.render.hud.HUDLayout")
local ObjectRenderer = require("necro.render.level.ObjectRenderer")
local OutlineFilter = require("necro.render.filter.OutlineFilter")
local Random = require("system.utils.Random")
local Render = require("necro.render.Render")
local RenderTimestep = require("necro.render.RenderTimestep")
local Settings = require("necro.config.Settings")
local Theme = require("necro.config.Theme")
local Utilities = require("system.utils.Utilities")
local VertexAnimation = require("system.gfx.VertexAnimation")
local Vision = require("necro.game.vision.Vision")
local VisualExtent = require("necro.render.level.VisualExtent")

local ceil = math.ceil
local clamp = Utilities.clamp

event.updateVisuals.add("itemSpriteFrameXUseHolderDice", "equipmentSprite", function()
	for entity in ECS.entitiesWithComponents({ "D6_itemSpriteFrameXUseHolderDice" }) do
		local holder = ECS.getEntityByID(entity.item.holder)
		entity.spriteSheet.frameX = (holder and holder.D6_dice) and (holder.D6_dice.point + 1)
			or ECS.getEntityPrototype(entity.name).spriteSheet.frameX
	end
end)

event.updateVisuals.add("dynamicItemCopySpriteFrames", {
	order = "equipmentSprite",
	sequence = 1,
}, function()
	for entity in ECS.entitiesWithComponents({ "D6_dynamicItemCopySpriteFrames" }) do
		entity.DynChar_dynamicItem.frameX = entity.spriteSheet.frameX - 1
		entity.DynChar_dynamicItem.frameY = entity.spriteSheet.frameY - 1
	end
end)

D6Visual.filterColorCollectorGetPath = CommonFilter.register("D6_colorCollector", { image = true }, {}, function(args)
	local colorSet = {}
	do
		local array = args.image.getArray()
		local getA = Color.getA
		local black = Color.BLACK
		for i = Bitmap.HEADER_SIZE, args.image.getWidth() * args.image.getHeight() + Bitmap.HEADER_SIZE - 1 do
			local color = array[i]
			if color ~= black and getA(color) == 255 then
				colorSet[color] = (colorSet[color] or 0) + 1
			end
		end
	end

	local out
	do
		local width = 0
		for _, count in pairs(colorSet) do
			width = width + ceil(math.sqrt(count))
		end
		out = Bitmap.new(width, 1)
	end

	local setPixel = out.setPixel
	local i = 0
	for color, count in Utilities.sortedPairs(colorSet) do
		for _ = 1, ceil(math.sqrt(count)) do
			setPixel(i, 0, color)
			i = i + 1
		end
	end

	return out
end)

local function playDicePointDamageParticle(ev)
	if Vision.isVisible(ev.x, ev.y) then
		local id, turnID = ev.id, ev.turnID
		local x, y = Render.tileCenter(ev.x, ev.y)
		local size = ev.size or 1

		x = x - size * 0.5
		y = y - size * 0.5

		local texture = D6Visual.filterColorCollectorGetPath({ image = ev.texture })
		local w = GFX.getImageWidth(texture)

		local draw = Render.getBuffer(Render.Buffer.PARTICLE).draw
		local visual = {
			rect = { 0, 0, size, size },
			texture = texture,
			texRect = { 0, 0, 1, 1 },
			color = Color.WHITE,
			anim = VertexAnimation.transientLinearFreezable(0, -ev.zVelocity, 0.3),
		}

		for i = 1, ev.particleCount do
			local time = ev.time - Random.float3(id, turnID, i * 6 + 4) * ev.maxDelay
			local alpha = Utilities.lerp(ev.minOpacity, 1, Random.float3(id, turnID, i * 6 + 6))

			alpha = alpha * Utilities.step(0, time) * clamp(0, 1 - (time - ev.fadeDelay) / ev.fadeTime, 1)

			local angle = Random.float3(id, turnID, i * 6 + 2) * math.pi * 2
			local r = math.sqrt(Random.float3(id, turnID, i * 6 + 3)) * ev.radius
			local dx, dy = r * math.cos(angle), r * math.sin(angle)
			local z = Random.float3(id, turnID, i * 6 + 5) * ev.radius

			z = z + (ev.zVelocity - ev.gravity * 0.5 * time) * time
			visual.rect[1] = x + dx
			visual.rect[2] = y + dy - z
			visual.texRect[1] = Random.noise3(id, turnID, i * 6 + 1, w)
			visual.z = y + dy - 24
			visual.color = Color.opacity(alpha)

			draw(visual)
		end
	end
end

event.particle.add("dicePointDamageParticle", "dicePointDamageParticle", function(ev)
	local success, message = pcall(playDicePointDamageParticle, ev)
	if not success then
		log.error("Error render `dicePointDamageParticle`: %s", message)
	end
end)

local function renderLuckyPointHintFilterHolder(entity)
	return not (entity.D6_diceFaceSprite and entity.position)
end

event.render.add("renderItemLuckyPointHints", {
	order = "hintLabels",
	sequence = 1,
}, function()
	local holders =
		Utilities.removeIf(Utilities.arrayCopy(Focus.getAll(Focus.Flag.HUD)), renderLuckyPointHintFilterHolder)
	if not holders[1] then
		return
	end

	local draw = Render.getBuffer(Render.Buffer.OBJECT).draw
	local drawArgs

	for entity in ECS.entitiesWithComponents({ "D6_equipDiceHint" }) do
		if entity.visibility.fullyVisible and not (entity.silhouette and entity.silhouette.active) then
			local holder = holders[1]
			if holders[2] then
				local x = entity.position.x
				local y = entity.position.y
				local nearestSquareDistance = Utilities.squareDistance(x - holder.position.x, y - holder.position.y)

				for i = 2, #holders do
					local holder2 = holders[i]
					local squareDistance = Utilities.squareDistance(x - holder2.position.x, y - holder2.position.y)
					if squareDistance < nearestSquareDistance then
						nearestSquareDistance = squareDistance
						holder = holder2
					end
				end
			end

			local texRect = holder.D6_diceFaceSprite.texRectMap[entity.D6_equipDice.value]
			if texRect then
				local x, y = VisualExtent.getTileCenter(entity)

				drawArgs = drawArgs or { color = Color.opacity(0.5), rect = { 0, 0, 0, 0 } }
				drawArgs.texture = holder.D6_diceFaceSprite.texture
				drawArgs.texRect = texRect
				drawArgs.rect[1] = x - texRect[3] * 0.5
				drawArgs.rect[2] = y
					- texRect[4] * 0.5
					+ (
						(entity.sale and entity.sale.priceTag ~= 0) and entity.D6_equipDiceHint.offsetYOnSale
						or entity.D6_equipDiceHint.offsetY
					)
				drawArgs.rect[3] = texRect[3]
				drawArgs.rect[4] = texRect[4]
				drawArgs.z = y - 24.5

				draw(drawArgs)
			end
		end
	end
end)

D6Visual.PreviewTweenAnimation = "D6_PreviewTween"

SettingPreview = Settings.overridable.percent({
	id = "preview",
	name = "Preview number opacity factor",
	order = 10,
	default = 0.7,
})

event.objectMove.add("playDicePreviewTween", {
	filter = "D6_dicePreview",
	order = "hasMoved",
	sequence = 6.6,
}, function(ev)
	if ev.entity.hasMoved.value then
		AnimationTimer.play(ev.entity.id, D6Visual.PreviewTweenAnimation)
	end
end)

local function drawDicePointDamagePreview(entity, tileX, tileY, buffer)
	local targets = Attack.getAttackableEntitiesOnTile(entity, tileX, tileY)
	if not targets[1] then
		return
	end

	Utilities.removeIf(targets, function(target)
		return not (target.sprite and entity.D6_dice.point == D6.getHealthDice(target))
	end)

	local target = targets[1]
	if target then
		local factor = Utilities.lerp(SettingPreview, 1, SettingPreview)
		local time = AnimationTimer.getTime(entity.id)
		local visual = OutlineFilter.getEntityVisual(target, nil, OutlineFilter.Mode.BASIC)
		visual.color = Color.hsv(
			math.sin(time * 7) * 0.016,
			0.75 + math.sin(time * 11) * 0.25,
			0.875 + math.sin(time * 13) * 0.125,
			factor
		)
		buffer.draw(visual)

		local srcX, srcY
		do
			local rect = VisualExtent.getRect(entity)
			srcX = rect[1]
			srcY = rect[2]
		end

		factor = Beatmap.getPrimary().getMusicBeatFraction() ^ 1.75
		visual.texture = entity.D6_dicePreview.pointDamageTexture
		visual.texRect[1] = 0
		visual.texRect[2] = 0
		visual.texRect[3], visual.texRect[4] = GFX.getImageSize(visual.texture)
		local w = visual.rect[3]
		local h = visual.rect[4]
		visual.rect[3] = visual.texRect[3] * Utilities.lerp(1.5, 1, factor)
		visual.rect[4] = visual.texRect[4] * Utilities.lerp(1.5, 1, factor)
		visual.color = Color.opacity((1.25 - factor) * SettingPreview)
		visual.angle = (Action.getDirection(tileX - entity.position.x, tileY - entity.position.y) - 1) * math.pi * -0.25
		visual.origin = {}

		factor = factor ^ 0.125
		visual.rect[1] = Utilities.lerp(srcX, visual.rect[1] + w * 0.5 - visual.rect[3] * 0.5, factor)
		visual.rect[2] = Utilities.lerp(srcY, visual.rect[2] + h * 0.5 - visual.rect[4] * 0.5, factor)
		buffer.draw(visual)
	end
end

local function drawDiceDirectionalPreviews(entity, opacity, directionList)
	local buffer = Render.getBuffer(Render.Buffer.ATTACHMENT)
	local defaultColor = Color.opacity(opacity)
	local animationFactor = AnimationTimer.getFactorClamped(
		entity.id,
		D6Visual.PreviewTweenAnimation,
		entity.tween.duration * 1.5
	) ^ 0.25
	local srcX, srcY = VisualExtent.getOrigin(entity)

	for _, direction in ipairs(directionList) do
		local texRect
		local definse
		local tileX, tileY = Action.getMovementOffset(direction)
		tileX = tileX + entity.position.x
		tileY = tileY + entity.position.y

		if not (entity.collisionCheckOnMove and Collision.check(tileX, tileY, entity.collisionCheckOnMove.mask)) then
			local form = D6.nextForm(entity.D6_dice.form, direction)
			local point = form and D6.getPoint(form)
			texRect = point and entity.D6_diceFaceSprite.texRectMap[point]
			definse = D6.checkDefense(entity, point)
		end

		if texRect then
			local dstX, dstY = Render.tileCenter(tileX, tileY)

			local factor = animationFactor - (0.0625 - (Beatmap.getPrimary().getMusicBeatFraction() ^ 1.25) * 0.0625)

			local x = Utilities.lerp(srcX, dstX, factor) - texRect[3] / 2
			local y = Utilities.lerp(srcY, dstY, factor)
				- texRect[4] / 2
				- entity.positionalSprite.offsetY
				+ entity.D6_dicePreview.faceOffsetY

			buffer.draw({
				texture = entity.D6_diceFaceSprite.texture,
				texRect = texRect,
				rect = { x, y, texRect[3], texRect[4] },
				color = definse and Color.fade(Theme.Color.HIGHLIGHT, opacity) or defaultColor,
				z = entity.shadowPosition.y + entity.shadow.offsetZ + y,
			})
		elseif entity.D6_dicePointDamage then
			drawDicePointDamagePreview(entity, tileX, tileY, buffer)
		end
	end
end

local function drawDicePointDefensePreview(entity, opacity, factor)
	if not entity.D6_dicePreview then
		return
	end

	factor = factor
		or AnimationTimer.getFactorClamped(entity.id, D6Visual.PreviewTweenAnimation, entity.tween.duration * 1.375)
			^ 0.5
	factor = clamp(0, factor - (0.2 - (Beatmap.getPrimary().getMusicBeatFraction() ^ 2) * 0.2), 1)

	local x = entity.sprite.x + entity.sprite.width * 0.5
	local y = entity.sprite.y + entity.sprite.height * 0.5
	local w, h = GFX.getImageSize(entity.D6_dicePreview.pointDefenseTexture)

	local maxScale = 3
	w = w * Utilities.lerp(maxScale, 1, factor)
	h = h * Utilities.lerp(maxScale, 1, factor)

	Render.getBuffer(Render.Buffer.ATTACHMENT).draw({
		texture = entity.D6_dicePreview.pointDefenseTexture,
		rect = {
			x - w * 0.5,
			y - h * 0.5,
			w,
			h,
		},
		color = Color.opacity(factor * opacity),
		z = entity.sprite.y + (entity.rowOrder and entity.rowOrder.z or 0) + 1,
	})

	return factor
end

event.render.add("renderDicePreviews", "tells", function()
	if SettingPreview <= 0 or CurrentLevel.isSafe() then
		return
	end

	local directionList
	for _, entity in ipairs(Focus.getAll(Focus.Flag.HUD)) do
		if
			entity.D6_dicePreview
			and entity.gameObject.tangible
			and entity.sprite.visible
			and (not entity.beatDelay or entity.beatDelay.counter <= 0)
			and (not entity.descent or not entity.descent.active)
			and (not entity.grabbable or not entity.grabbable.isGrabbed)
			and (not entity.sinkable or not entity.sinkable.sunken)
			and (not entity.slide or entity.slide.direction == 0)
			and (not entity.stun or entity.stun.counter <= 1)
		then
			directionList = directionList
				or { Action.Direction.RIGHT, Action.Direction.UP, Action.Direction.LEFT, Action.Direction.DOWN }
			drawDiceDirectionalPreviews(entity, SettingPreview, directionList)
			--- drawDicePointDefensePreview(entity, SettingPreview) -- Defensing shield should be an effect, not preview.
		end
	end
end)

local dicePointDefenseParticleCache = setmetatable({}, { __mode = "k" })

event.render.add("renderDicePointDefensePreview", "particles", function()
	local opacity = 0.75
	local time = AnimationTimer.getTime()

	for entity in ECS.entitiesWithComponents({ "D6_dicePointDefense", "sprite" }) do
		if entity.gameObject.tangible and entity.sprite.visible and D6.checkDefense(entity) then
			local factor = drawDicePointDefensePreview(entity, opacity)
			if factor then
				local particle = dicePointDefenseParticleCache[entity] or { factor = 0, time = 0 }
				particle.factor = factor
				particle.time = time
				dicePointDefenseParticleCache[entity] = particle
			end
		end
	end

	for entity, particle in pairs(dicePointDefenseParticleCache) do
		if time > particle.time then
			local factor = particle.factor - (time - particle.time) ^ 0.25
			if factor <= 0 or not entity.D6_dicePreview then
				dicePointDefenseParticleCache[entity] = nil
			else
				drawDicePointDefensePreview(entity, opacity, factor)
			end
		end
	end
end)

event.inventoryHUDRenderSlot.add("drawLuckyPoint", {
	filter = "D6_equipDiceSprite",
	order = "renderSprite",
	sequence = -6,
}, function(ev)
	if
		ev.holder.D6_inventoryApplyEquipDice
		and ev.holder.D6_diceFaceSprite
		and ev.drawArgs
		and Utilities.arrayFind(ev.holder.D6_inventoryApplyEquipDice.slots, ev.item.itemSlot.name)
	then
		local texRect = ev.holder.D6_diceFaceSprite.texRectMap[ev.item.D6_equipDice.value]
		if type(texRect) == "table" then
			local origRect = ev.drawArgs.rect
			local origTexture = ev.drawArgs.texture
			local origTexRect = ev.drawArgs.texRect
			local origZ = ev.drawArgs.z

			ev.drawArgs.rect = {
				origRect[1] + origRect[3] * 0.2 - origTexRect[3] * 0.5,
				origRect[2] + origRect[4] * 0.5,
				texRect[3] * 2,
				texRect[4] * 2,
			}
			ev.drawArgs.texture = ev.holder.D6_diceFaceSprite.texture
			ev.drawArgs.texRect = texRect
			ev.drawArgs.z = (ev.item.item and ev.item.item.equipped) and (origZ - 1e-5) or (origZ + 1e-5)

			ev.buffer.draw(ev.drawArgs)

			ev.drawArgs.rect = origRect
			ev.drawArgs.texture = origTexture
			ev.drawArgs.texRect = origTexRect
			ev.drawArgs.z = origZ
		end
	end
end)

local function centerWithinRect(outerRect, width, height)
	return {
		outerRect[1] + (outerRect[3] - width) * 0.5,
		outerRect[2] + (outerRect[4] - height) * 0.5,
		width,
		height,
	}
end

event.renderPlayerListEntry.add("renderSprite", {
	filter = "D6_diceOverridePlayerListSprite",
	order = "sprite",
	sequence = -6,
}, function(ev)
	local drawArgs = ObjectRenderer.getObjectVisual(ev.spriteEntity)
	local headWidth = 20
	local texture = ev.entity.D6_diceOverridePlayerListSprite.texture
	local size = GFX.getImageHeight(texture)

	drawArgs.texture = texture
	drawArgs.texRect = { (ev.entity.D6_dice.point - 1) * size, 0, size, size }
	drawArgs.rect = centerWithinRect({
		ev.slotRect[1] + (ev.spriteOffsetX or 0) * ev.scale,
		ev.slotRect[2] + (ev.spriteOffsetY or 0) * ev.scale,
		headWidth * ev.scale,
		ev.slotRect[4],
	}, drawArgs.rect[3] * ev.scale, drawArgs.rect[4] * ev.scale)
	drawArgs.anim = 0
	drawArgs.color = Color.fade(drawArgs.color, ev.opacity)
	drawArgs.z = 0

	ev.buffer.draw(drawArgs)
end)

SettingHealthHitDistance = Settings.overridable.number({
	id = "healthHitDistance",
	name = "Enemy hit number show distance",
	order = 20,
	default = 2.5,
	minimum = 0,
	sliderMaximum = 12,
	step = 0.5,
})

SettingHealthHitOpacity = Settings.overridable.percent({
	id = "healthHitOpacity",
	name = "Enemy hit number opacity",
	order = 21,
	default = 0.8,
})

local entityHealthHitDiceCaches = setmetatable({}, { __mode = "k" })

event.render.add("renderHealthHitDices", "tells", function()
	if SettingHealthHitDistance <= 0 or SettingHealthHitOpacity <= 0 then
		Utilities.clearTable(entityHealthHitDiceCaches)

		return
	end

	local focusedEntities = Utilities.removeIf(Utilities.arrayCopy(Focus.getAll(Focus.Flag.HUD)), function(e)
		return not (e.D6_dicePointDamage and e.D6_diceFaceSprite and e.position)
	end)

	if not focusedEntities[1] then
		Utilities.clearTable(entityHealthHitDiceCaches)

		return
	end

	local focusedSet = Utilities.listToSet(focusedEntities)

	local squareDistance = Utilities.squareDistance
	local maximumSquareDistance = SettingHealthHitDistance * SettingHealthHitDistance
	local maxOpacity = SettingHealthHitOpacity
	local lerpFactor = 1 - 1e-15 ^ RenderTimestep.getDeltaTime()
	lerpFactor = lerpFactor * lerpFactor
	local opacityFactor = Utilities.lerp(Beatmap.getPrimary().getMusicBeatFraction(), 1, 0.5)
	local draw = Render.getBuffer(Render.Buffer.ATTACHMENT).draw
	local drawArgs

	for entity in ECS.entitiesWithComponents({ "enemy", "health", "position", "visibility" }) do
		if
			focusedSet[entity]
			or not entity.visibility.fullyVisible
			or (entity.silhouette and entity.silhouette.active)
		then
			goto continue
		end

		local show
		local p1 = entity.position
		for _, focusedEntity in ipairs(focusedEntities) do
			local p2 = focusedEntity.position
			if squareDistance(p1.x - p2.x, p1.y - p2.y) <= maximumSquareDistance then
				show = focusedEntity.D6_diceFaceSprite
				break
			end
		end

		local cache = entityHealthHitDiceCaches[entity]
		if show then
			cache = cache or { diceFaceSprite = false, opacity = 0 }
			cache.diceFaceSprite = show
			cache.opacity = Utilities.lerp(cache.opacity, maxOpacity, lerpFactor)
			entityHealthHitDiceCaches[entity] = cache
		elseif cache then
			cache.opacity = Utilities.lerp(cache.opacity, 0, lerpFactor)
			entityHealthHitDiceCaches[entity] = cache.opacity > 1e-6 and cache or nil
		end

		local texRect = cache and cache.diceFaceSprite.texRectMap[D6.getHealthDice(entity)]
		if texRect then
			local x, y
			if entity.healthBar and entity.healthBar.visible then
				x = VisualExtent.getOrigin(entity) + entity.healthBar.offsetX
				y = entity.shadowPosition.y + entity.healthBar.offsetY - texRect[3]
			else
				x, y = VisualExtent.getPosition(entity, nil, -0.25)
			end

			drawArgs = drawArgs or { color = -1, rect = { 0, 0, 0, 0 } }
			drawArgs.texture = cache.diceFaceSprite.texture
			drawArgs.texRect = texRect
			drawArgs.rect[1] = x - texRect[3] * 0.5
			drawArgs.rect[2] = y - texRect[4] * 0.5
			drawArgs.rect[3] = texRect[3]
			drawArgs.rect[4] = texRect[4]
			drawArgs.color = Color.fade(Theme.Color.STATUS_WARNING, cache.opacity * opacityFactor)
			drawArgs.z = y + 23

			draw(drawArgs)
		end

		::continue::
	end
end)

SettingHUD = Settings.overridable.bool({
	id = "hud",
	name = "Override equipment HUD",
	order = 1,
	default = true,
	setter = HUDLayout.updateElements,
})

event.collectHUDElements.add("overrideEquipment", "custom", function(ev)
	if SettingHUD then
		local element = ev.elements[HUDLayout.Element.EQUIPMENT]
		if element then
			element.maxSize[1] = math.max(540, element.maxSize[1] or 0)
		end
	end
end)
