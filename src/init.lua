-- Copyright (C) 2023 Tria
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local SettingsHandler = require(ReplicatedStorage.shared.OSLib.SettingsHandler)
local PlayerStates = require(ReplicatedStorage.shared.PlayerStates)
local Types = require(script.Types)

local CONTEXT_ERROR = "'%s' Cannot be called from the %s" -- Error which shows up when a function is ran on the wrong context
local IS_SERVER = RunService:IsServer()
local LIQUID_COLORS = {
	water = Color3.fromRGB(33, 84, 185),
	acid = Color3.fromRGB(0, 255, 0),
	lava = Color3.fromRGB(255, 0, 0),
}

local Alert, Sound, Signal
if IS_SERVER then
	Signal = require(ReplicatedStorage.Packages.Signal)
else
	Alert = require(game.Players.LocalPlayer.PlayerScripts.client.Alert)
	Sound = require(game.Players.LocalPlayer.PlayerScripts.client.Sound)
end

local MapLib: Types.MapLib = {}
MapLib.__index = MapLib

function MapLib.new(map, MapHandler)
	local self: Types.MapLib = setmetatable({}, MapLib)

	self.map = map
	self.Map = map
	self._MapHandler = MapHandler

	return self
end

function MapLib:Alert(message: string, color: Color3?, length: number?)
	if IS_SERVER then
		ReplicatedStorage.Remotes.Misc.SendAlert:FireAllClients(message, color, length, true)
	else
		Alert.new(message, color, length, true)
	end
end

function MapLib:ChangeMusic(musicId: number, volume: number?, startTick: number?)
	if IS_SERVER then
		ReplicatedStorage.Remotes.Misc.ChangeMusic:FireAllClients(musicId, volume, (startTick or 0))
	else
		Sound:ChangeMusic(musicId, volume, startTick)
	end
end

function MapLib:GetButtonEvent(buttonId: number | string)
	if IS_SERVER then
		if tonumber(buttonId) then
			-- Normal button
			return self._MapHandler.ButtonHandler:GetButton(buttonId).Activated
		else
			-- Path button
			local event = Signal.new()
			self._MapHandler.ButtonHandler
				:GetButton(tonumber(buttonId:sub(1, #buttonId - 1))).Activated
				:Connect(function(player, isLastButton, longId)
					event:Fire(player, isLastButton, longId)
				end)
			return event
		end
	else
		error(CONTEXT_ERROR:format("MapLib:GetButtonEvent", "client"), 2)
	end
end

function MapLib:Survive(player: Player)
	if IS_SERVER then
		if not player then
			return error("Player does not exist", 2)
		end
		PlayerStates:SetPlayerState(player, PlayerStates.SURVIVED)
		ReplicatedStorage.Remotes.Misc.SendAlert:FireClient(player, "Survived", "green", 2.5)
	else
		error(CONTEXT_ERROR:format("MapLib:SurvivePlayer", "client"), 2)
	end
end

function MapLib:SetLiquidType(liquid: BasePart, liquidType: string)
	task.spawn(function()
		local color = LIQUID_COLORS[liquidType]
		if self.map and not color then
			local custom = self.map.Settings.Liquids:FindFirstChild(liquidType)
			color = custom and SettingsHandler:GetValue(custom, "Color") or Color3.new()
		end

		TweenService:Create(liquid, TweenInfo.new(1), { Color = color }):Play()
		task.wait(1)
		SettingsHandler:SetValue(liquid, "Type", liquidType)
	end)
end

local function move(moveable: PVInstance, movement: Vector3, duration: number?, relative: boolean?)
	if duration == 0 or duration == nil then
		return moveable:PivotTo(
			relative and moveable:GetPivot() * CFrame.new(movement) or moveable:GetPivot() + movement
		)
	end

	local moved = Vector3.zero
	local move = movement / duration
	local endTick = tick() + duration
	local connection
	connection = RunService.PreSimulation:Connect(function(deltaTime)
		if tick() < endTick then
			moved += move * deltaTime
			moveable:PivotTo(
				relative and moveable:GetPivot() * CFrame.new(move * deltaTime)
					or moveable:GetPivot() + (move * deltaTime)
			)
		else
			connection:Disconnect()
			moveable:PivotTo(
				relative and moveable:GetPivot() * CFrame.new(movement - moved)
					or moveable:GetPivot() + (movement - moved)
			)
		end
	end)
end

function MapLib:Move(moveable: PVInstance, movement: Vector3, duration: number?)
	task.spawn(move, moveable, movement, duration)
end
function MapLib:MoveRelative(moveable: PVInstance, movement: Vector3, duration: number?)
	task.spawn(move, moveable, movement, duration, true)
end
MapLib.MovePart = MapLib.Move
MapLib.MovePartLocal = MapLib.MoveRelative
MapLib.MoveModel = MapLib.Move
MapLib.MoveModelLocal = MapLib.MoveRelative

function MapLib:GetPlayers()
	return PlayerStates:GetPlayersWithState(PlayerStates.GAME)
end

local features: {[string]: Feature} = {}
for i, v in next, script.Features do
	features[v.Name] = require(v)
end
---@typecheck mode: nocheck - Some reason this typing does not work correctly
function MapLib:GetFeature(name)
	local feature = features[name]
	if feature then
		if feature.context == "client" and IS_SERVER or feature.context == "server" and not IS_SERVER then
			error(("Feature '%s' can only be used on the '%s'"):format(name, feature.context), 2)
		end
		return feature.new and feature.new(MapLib) or feature
	else
		error(("Cannot find feature '%s'"):format(name), 2)
	end
end

return MapLib