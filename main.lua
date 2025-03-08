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
        player_speed = 135, 
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
    free_vehicles = { Camaro = true, Jeep = true },
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
    local distance = math.huge;
    local nearest;

    local tried = tried or { };
    
    for index, value in next, dependencies.door_positions do
        if not table.find(tried, value) then
            local magnitude = (value.position - Character.HumanoidRootPart.Position).Magnitude;
            
            if magnitude < distance then 
                distance = magnitude;
                nearest = value;
            end;
        end;
    end;

    table.insert(tried, nearest);

    utilities:toggle_door_collision(nearest.instance, false);

    local path = dependencies.variables.path;
    path:ComputeAsync(Character.HumanoidRootPart.Position, nearest.position);

    if path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints();

        for index = 1, #waypoints do 
            local waypoint = waypoints[index];
            
            Character.HumanoidRootPart.CFrame = CFrame.new(waypoint.Position + Vector3.new(0, 2.5, 0)); -- walking movement is less optimal

            if not workspace:Raycast(Character.HumanoidRootPart.Position, dependencies.variables.up_vector, dependencies.variables.raycast_params) then
                utilities:toggle_door_collision(nearest.instance, true);

                return;
            end;

            task.wait(0.05);
        end;
    end;

    utilities:toggle_door_collision(nearest.instance, true);

    movement:pathfind(tried);
end;

--// function to interpolate characters position to a position

function movement:move_to_position(part, cframe, speed, car, target_vehicle, tried_vehicles)
    local vector_position = cframe.Position;
    
    if not car and workspace:Raycast(part.Position, dependencies.variables.up_vector, dependencies.variables.raycast_params) then -- if there is an object above us, use pathfind function to get to a position with no collision above
        movement:pathfind();
        task.wait(0.5);
    end;
    
    local y_level = 350;
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
            for distance = 5, 300, 5 do 
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

--// main teleport function (not returning a new function directly because of recursion)

local function teleport(cframe, tried)
    local relative_position = (cframe.Position - Character.HumanoidRootPart.Position);
    local target_distance = relative_position.Magnitude;

    if target_distance <= 20 and not workspace:Raycast(Character.HumanoidRootPart.Position, relative_position.Unit * target_distance, dependencies.variables.raycast_params) then 
        Character.HumanoidRootPart.CFrame = cframe; 
        return;
    end; 

    local tried = tried or { };
    local nearest_vehicle = utilities:get_nearest_vehicle(tried);

    if not nearest_vehicle then
        return;
    end
    
    local vehicle_object = nearest_vehicle and nearest_vehicle.ValidRoot;

    dependencies.variables.teleporting = true;

    if vehicle_object then 
        local vehicle_distance = (vehicle_object.Seat.Position - Character.HumanoidRootPart.Position).Magnitude;

        if target_distance < vehicle_distance then
            movement:move_to_position(Character.HumanoidRootPart, cframe, dependencies.variables.player_speed);
        else 
            if vehicle_object.Seat.PlayerName.Value ~= Player.Name then
                movement:move_to_position(Character.HumanoidRootPart, vehicle_object.Seat.CFrame, dependencies.variables.player_speed, false, vehicle_object, tried);

                dependencies.variables.stopVelocity = true;

                local enter_attempts = 1;

                repeat 
                    task.wait(0.1)
                    
                    if nearest_vehicle and nearest_vehicle.Callback then
                        nearest_vehicle:Callback(true)
                    end
                
                    enter_attempts = enter_attempts + 1
                until enter_attempts == 10 or (vehicle_object.Seat:FindFirstChild("PlayerName") and vehicle_object.Seat.PlayerName.Value == Player.Name)

                dependencies.variables.stopVelocity = false;

                if vehicle_object.Seat.PlayerName.Value ~= Player.Name then
                    table.insert(tried, vehicle_object);

                    return teleport(cframe, tried or { vehicle_object });
                end;
            end;

            movement:move_to_position(vehicle_object.Engine, cframe, dependencies.variables.vehicle_speed, true);

            repeat
                task.wait(0.15);
                dependencies.modules.character_util.OnJump();
            until vehicle_object.Seat.PlayerName.Value ~= Player.Name;
            
            -- Wait a bit to allow falling naturally
            task.wait(0.5)
            
            -- Ensure character is fully grounded before continuing
            local function is_grounded()
                local ray = workspace:Raycast(Character.HumanoidRootPart.Position, Vector3.new(0, -10, 0), dependencies.variables.raycast_params)
                return ray ~= nil
            end
            
            -- Force character to fall if not on ground
            local fall_timeout = 5
            local elapsed_time = 0
            
            while not is_grounded() and elapsed_time < fall_timeout do
                Character.HumanoidRootPart.Velocity = Vector3.new(0, -50, 0) -- Force downward movement
                task.wait(0.2)
                elapsed_time = elapsed_time + 0.2
            end
            
            if not is_grounded() then
                warn("Character is still stuck in the air after timeout. Attempting manual reset.")
                Character.HumanoidRootPart.CFrame = workspace.SpawnLocation.CFrame -- Move to spawn to reset
                task.wait(1) -- Wait for physics to stabilize
            end
            
            -- Now that we are on the ground, find the nearest vehicle
            local new_nearest_vehicle = utilities:get_nearest_vehicle({})
            if new_nearest_vehicle then
                local new_vehicle_object = new_nearest_vehicle.ValidRoot
                movement:move_to_position(Character.HumanoidRootPart, new_vehicle_object.Seat.CFrame, dependencies.variables.player_speed, false, new_vehicle_object)
            end
            
        end;
    else
        movement:move_to_position(Character.HumanoidRootPart, cframe, dependencies.variables.player_speed);
    end;

    task.wait(0.5);
    dependencies.variables.teleporting = false;
end;

return teleport;
