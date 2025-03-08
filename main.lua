---@diagnostic disable: undefined-global, lowercase-global, unused-function, unused-local, empty-block, unbalanced-assignments, deprecated, undefined-field, code-after-break, redundant-parameter

--// services

local replicated_storage = game:GetService("ReplicatedStorage");
local run_service = game:GetService("RunService");
local pathfinding_service = game:GetService("PathfindingService");
local players = game:GetService("Players");
local tween_service = game:GetService("TweenService");

--// variable

local Players = game:GetService("Players");
local Player = Players.LocalPlayer or Players:WaitForChild("LocalPlayer", 9e9);
local Character = Player.Character or Player:WaitForChild("Character", 9e9);

local dependencies = {
    variables = {
        up_vector = Vector3.new(0, 350, 0),
        raycast_params = RaycastParams.new(),
        path = pathfinding_service:CreatePath({WaypointSpacing = 3}),
        player_speed = 100, 
        vehicle_speed = 200,
        teleporting = false,
        stopVelocity = false
    },
    modules = {
        ui = require(replicated_storage.Module.UI),
        store = require(replicated_storage.App.store),
        player_utils = require(replicated_storage.Game.PlayerUtils),
        vehicle_data = require(replicated_storage.Game.Garage.VehicleData),
        character_util = require(replicated_storage.Game.CharacterUtil),
        paraglide = require(replicated_storage.Game.Paraglide)
    },
    helicopters = { Heli = true },
    motorcycles = { Volt = true },
    free_vehicles = { Camaro = true },
    unsupported_vehicles = { SWATVan = true },
    door_positions = { }    
};

local movement = { };
local utilities = { };

--// function to toggle if a door can be collided with

function utilities:toggle_door_collision(door, toggle)
    for index, child in next, door.Model:GetChildren() do
        if child:IsA("BasePart") then 
            child.CanCollide = toggle;
        end; 
    end;
end;

--// function to get the nearest vehicle that can be entered

function utilities:get_nearest_vehicle(tried)
    local nearest, distance = nil, math.huge
    local playerRoot = Character and Character:FindFirstChild("HumanoidRootPart")
    if not playerRoot then return nil end

    local playerPosition = playerRoot.Position

    local validVehicles = {}

    for _, action in pairs(dependencies.modules.ui.CircleAction.Specs) do
        local vehicle = action.ValidRoot

        if action.IsVehicle and action.Enabled and action.Name == "Enter Driver" and action.ShouldAllowEntry 
            and not table.find(tried, vehicle)
            and workspace.VehicleSpawns:FindFirstChild(vehicle.Name)
            and not dependencies.unsupported_vehicles[vehicle.Name]
            and (dependencies.modules.store._state.garageOwned.Vehicles[vehicle.Name] or dependencies.free_vehicles[vehicle.Name])
            and not vehicle.Seat.Player.Value
            and not workspace:Raycast(vehicle.Seat.Position, dependencies.variables.up_vector, dependencies.variables.raycast_params) 
        then
            local magnitude = (vehicle.Seat.Position - playerPosition).Magnitude
            table.insert(validVehicles, { action = action, magnitude = magnitude })
        end
    end

    table.sort(validVehicles, function(a, b) return a.magnitude < b.magnitude end)

    return validVehicles[1] and validVehicles[1].action or nil
end

--// function to pathfind to a position with no collision above

function movement:pathfind(tried)
    tried = tried or {}
    local nearest, distance = nil, math.huge

    for _, door in ipairs(dependencies.door_positions) do
        if not table.find(tried, door) then
            local magnitude = (door.position - Character.HumanoidRootPart.Position).Magnitude
            if magnitude < distance then
                distance = magnitude
                nearest = door
            end
        end
    end

    if not nearest then
        return
    end

    table.insert(tried, nearest)


    utilities:toggle_door_collision(nearest.instance, false)

    local path = dependencies.variables.path
    local success, err = pcall(function()
        path:ComputeAsync(Character.HumanoidRootPart.Position, nearest.position)
    end)

    if not success or path.Status ~= Enum.PathStatus.Success then
        warn("⚠️ Pathfinding failed: " .. (err or "Invalid path"))
        utilities:toggle_door_collision(nearest.instance, true)
        return movement:pathfind(tried)
    end

    local waypoints = path:GetWaypoints()
    for _, waypoint in ipairs(waypoints) do
        Character.Humanoid:MoveTo(waypoint.Position + Vector3.new(0, 1.5, 0))
        Character.Humanoid.MoveToFinished:Wait()

        if not workspace:Raycast(Character.HumanoidRootPart.Position, dependencies.variables.up_vector, dependencies.variables.raycast_params) then
            utilities:toggle_door_collision(nearest.instance, true)
            return
        end
    end

    utilities:toggle_door_collision(nearest.instance, true)

    movement:pathfind(tried)
end

--// function to interpolate characters position to a position

function movement:move_to_position(part, cframe, speed, car, target_vehicle, tried_vehicles)
    local vector_position = cframe.Position;
    
    if not car and workspace:Raycast(part.Position, dependencies.variables.up_vector, dependencies.variables.raycast_params) then -- if there is an object above us, use pathfind function to get to a position with no collision above
        movement:pathfind();
        task.wait(0.5);
    end;
    
    local y_level = 500;
    local higher_position = Vector3.new(vector_position.X, y_level, vector_position.Z);

    repeat
        local velocity_unit = (higher_position - part.Position).Unit * speed;
        part.Velocity = Vector3.new(velocity_unit.X, 0, velocity_unit.Z);

        task.wait();

        part.CFrame = CFrame.new(part.CFrame.X, y_level, part.CFrame.Z);

        if target_vehicle and target_vehicle.Seat.Player.Value then
            table.insert(tried_vehicles, target_vehicle);

            local nearest_vehicle = utilities:get_nearest_vehicle(tried_vehicles);
            local vehicle_object = nearest_vehicle and nearest_vehicle.ValidRoot;

            if vehicle_object then 
                movement:move_to_position(Character.HumanoidRootPart, vehicle_object.Seat.CFrame, 135, false, vehicle_object);
            end;

            return;
        end;
    until (part.Position - higher_position).Magnitude < 10;

    part.CFrame = CFrame.new(part.Position.X, vector_position.Y, part.Position.Z);
    part.Velocity = Vector3.zero;
end;

--// raycast filter

dependencies.variables.raycast_params.FilterType = Enum.RaycastFilterType.Blacklist;
dependencies.variables.raycast_params.FilterDescendantsInstances = { Character, workspace.Vehicles, workspace:FindFirstChild("Rain") };

workspace.ChildAdded:Connect(function(child)
    if child.Name == "Rain" then 
        table.insert(dependencies.variables.raycast_params.FilterDescendantsInstances, child);
    end;
end);

Player.CharacterAdded:Connect(function(character)
    table.insert(dependencies.variables.raycast_params.FilterDescendantsInstances, character);
end);

--// get free vehicles, owned helicopters, motorcycles and unsupported/new vehicles

for index, vehicle_data in next, dependencies.modules.vehicle_data do
    if vehicle_data.Type == "Heli" then
        dependencies.helicopters[vehicle_data.Make] = true;
    elseif vehicle_data.Type == "Motorcycle" then
        dependencies.motorcycles[vehicle_data.Make] = true;
    end;

    if vehicle_data.Type ~= "Chassis" and vehicle_data.Type ~= "Motorcycle" and vehicle_data.Type ~= "Heli" and vehicle_data.Type ~= "DuneBuggy" and vehicle_data.Make ~= "Volt" then -- weird vehicles that are not supported
        dependencies.unsupported_vehicles[vehicle_data.Make] = true;
    end;
    
    if not vehicle_data.Price then
        dependencies.free_vehicles[vehicle_data.Make] = true;
    end;
end;

--// get all positions near a door which have no collision above them

for index, value in next, workspace:GetDescendants() do
    if value.Name:sub(-4, -1) == "Door" then 
        local touch_part = value:FindFirstChild("Touch");

        if touch_part and touch_part:IsA("BasePart") then
            for distance = 5, 100, 5 do 
                local forward_position, backward_position = touch_part.Position + touch_part.CFrame.LookVector * (distance + 3), touch_part.Position + touch_part.CFrame.LookVector * -(distance + 3); -- distance + 3 studs forward and backward from the door
                
                if not workspace:Raycast(forward_position, dependencies.variables.up_vector, dependencies.variables.raycast_params) then -- if there is nothing above the forward position from the door
                    table.insert(dependencies.door_positions, { instance = value, position = forward_position });

                    break;
                elseif not workspace:Raycast(backward_position, dependencies.variables.up_vector, dependencies.variables.raycast_params) then -- if there is nothing above the backward position from the door
                    table.insert(dependencies.door_positions, { instance = value, position = backward_position });

                    break;
                end;
            end;
        end;
    end;
end;

--// no fall damage or ragdoll


--// anti skydive

local oldIsFlying = dependencies.modules.paraglide.IsFlying
dependencies.modules.paraglide.IsFlying = function(...)
    local success, debugInfo = pcall(function() return debug.getinfo(2, "s") end)

    if success and debugInfo and debugInfo.source and dependencies.variables.teleporting then
        if debugInfo.source:find("Falling") then
            return true
        end
    end

    return oldIsFlying(...)
end

--// stop velocity

task.spawn(function()
    while task.wait(0.1) do
        if dependencies.variables.stopVelocity and Character and Character:FindFirstChild("HumanoidRootPart") then
            Character.HumanoidRootPart.Velocity = Vector3.zero;
        end;
    end;
end);

--// spawn vehicle

function is_inside()
    local hrp = Character.HumanoidRootPart
    local ray_direction = Vector3.new(0, 50, 0)
    local result = workspace:Raycast(hrp.Position, ray_direction)

    return result ~= nil
end

local function get_or_spawn_vehicle(preferred_vehicles, tried)
    tried = tried or {}

    -- Check if player is already in a vehicle before spawning
    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        local current_vehicle = player.Character.HumanoidRootPart.Parent
        if current_vehicle and current_vehicle:FindFirstChild("Seat") then
            if current_vehicle.Seat:FindFirstChild("Player") and current_vehicle.Seat.Player.Value == player then
                return current_vehicle -- Already in a vehicle, no need to spawn
            end
        end
    end

    -- Try spawning preferred vehicles
    for _, vehicle_name in ipairs(preferred_vehicles) do
        if not table.find(tried, vehicle_name) then
            game:GetService("ReplicatedStorage").GarageSpawnVehicle:FireServer("Chassis", vehicle_name)

            task.wait(2) -- Wait for the vehicle to spawn

            -- Find newly spawned vehicle
            for _, v in ipairs(workspace:GetChildren()) do
                if v.Name == vehicle_name and v:FindFirstChild("Seat") then
                    if not v.Seat.Player.Value then
                        return v -- Found a free vehicle
                    end
                end
            end

            table.insert(tried, vehicle_name)
        end
    end

    -- If no preferred vehicle is available, get the nearest usable vehicle
    local nearest_vehicle = utilities:get_nearest_vehicle(tried)

    if nearest_vehicle then
        return nearest_vehicle.ValidRoot
    end

    return nil -- No vehicle found
end

--// main teleport function (not returning a new function directly because of recursion)

local function is_inside()
    local hrp = Character.HumanoidRootPart
    local ray_direction = Vector3.new(0, 50, 0)
    local result = workspace:Raycast(hrp.Position, ray_direction)

    return result ~= nil
end

local function get_outside_position()
    local hrp = Character.HumanoidRootPart
    return hrp.Position + Vector3.new(10, 0, 10)
end

local function teleport(cframe, tried)
    local relative_position = (cframe.Position - Character.HumanoidRootPart.Position)
    local target_distance = relative_position.Magnitude

    if is_inside() then
        local outside_position = get_outside_position()
        movement:move_to_position(Character.HumanoidRootPart, CFrame.new(outside_position), dependencies.variables.player_speed)
        
        repeat task.wait(0.5) until not is_inside()
    end

    if target_distance <= 20 and not workspace:Raycast(Character.HumanoidRootPart.Position, relative_position.Unit * target_distance, dependencies.variables.raycast_params) then
        Character.HumanoidRootPart.CFrame = cframe
        return
    end

    tried = tried or {}
    local preferred_vehicles = { "Camaro" }
    local selected_vehicle = get_or_spawn_vehicle(preferred_vehicles, tried)

    if not selected_vehicle then
        return movement:move_to_position(Character.HumanoidRootPart, cframe, dependencies.variables.player_speed)
    end

    dependencies.variables.teleporting = true
    movement:move_to_position(Character.HumanoidRootPart, selected_vehicle.Seat.CFrame, dependencies.variables.player_speed, false, selected_vehicle, tried)

    dependencies.variables.stopVelocity = true
    local enter_attempts = 1

    repeat
        task.wait(0.1)
        enter_attempts = enter_attempts + 1
    until enter_attempts == 10 or selected_vehicle.Seat.Player.Value == Player

    dependencies.variables.stopVelocity = false

    if selected_vehicle.Seat.Player.Value ~= Player then
        table.insert(tried, selected_vehicle.Name)
        return teleport(cframe, tried)
    end

    movement:move_to_position(selected_vehicle.Engine, cframe, dependencies.variables.vehicle_speed, true)
    
    task.wait(0.5)
    dependencies.variables.teleporting = false
end

return teleport;
