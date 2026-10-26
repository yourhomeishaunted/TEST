--[[ services ]]

local cloneref = cloneref or function(obj)
    return obj
end

local Services = {
    players = cloneref(game:GetService("Players")),
    run_service = cloneref(game:GetService("RunService")),
    user_input = cloneref(game:GetService("UserInputService")),
}
Services.local_player = Services.players.LocalPlayer

--[[ extra vars ]]

local Constants = {
    fire_delay = 0.05,
    max_dist_sq = 1000 * 1000,
    scatter_range = 150,
    under = 6,
    behind = 3,
    melee = { Knife = true },
    rage_key = Enum.KeyCode.X,
    void_key = Enum.KeyCode.V,
}

local State = {
    camera = workspace.CurrentCamera,
    character = nil,
    root = nil,
    params = RaycastParams.new(),
    real_cf = nil,
    last_shot = 0,
    target = nil,
    flip = false,
    rage = false,
    void = false,
    desync = false,
    desync_con = nil,
}
State.params.FilterType = Enum.RaycastFilterType.Exclude

--[[ helpers ]]

local function on_char(char)
    State.character = char
    State.real_cf = nil
    State.params.FilterDescendantsInstances = { char }
    State.root = char:WaitForChild("HumanoidRootPart")
end

local function is_enemy(player)
    local team = player.Team
    return team == nil or team ~= Services.local_player.Team
end

local function is_alive(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function is_melee()
    local char = State.character
    local tool = char and char:FindFirstChildOfClass("Tool")
    return tool ~= nil and Constants.melee[tool.Name] == true
end

local function get_target() LPH_ATTRIBUTES(PRESET(FAST))
    local part
    local closest = Constants.max_dist_sq
    local origin = State.camera.CFrame.Position

    for _, player in Services.players:GetPlayers() do
        if player ~= Services.local_player and is_enemy(player) then
            local char = player.Character
            local head = char and char:FindFirstChild("Head")

            if head and is_alive(char) then
                local offset = head.Position - origin
                local d = offset:Dot(offset)

                if d < closest then
                    local hit = workspace:Raycast(origin, offset, State.params)
                    if hit == nil or hit.Instance:IsDescendantOf(char) then
                        closest = d
                        part = head
                    end
                end
            end
        end
    end

    return part
end

--[[ desync ]]

local function desync_out()
    local root = State.root
    if not root or not root.Parent then return end

    local cf = root.CFrame
    State.real_cf = cf

    if State.void then
        State.flip = not State.flip
        local part = State.rage and State.target or get_target()
        local hrp = part and part.Parent:FindFirstChild("HumanoidRootPart")

        if State.flip and hrp then
            local t = hrp.CFrame
            root.CFrame = is_melee() and t * CFrame.new(0, 0, Constants.behind) or t - Vector3.new(0, Constants.under, 0)
        else
            root.CFrame = CFrame.new(cf.X, workspace.FallenPartsDestroyHeight + 25, cf.Z)
        end
        return
    end

    local r = Constants.scatter_range
    root.CFrame = (cf + Vector3.new((math.random() * 2 - 1) * r, 0, (math.random() * 2 - 1) * r))
        * CFrame.Angles(0, math.random() * 6.2832, 0)
end

local function desync_back()
    local root, real = State.root, State.real_cf
    if root and real then
        root.CFrame = real
        State.real_cf = nil
    end
end

local function refresh_desync()
    local on = State.rage or State.void
    if on == State.desync then return end
    State.desync = on

    if on then
        State.desync_con = Services.run_service.Heartbeat:Connect(desync_out)
        Services.run_service:BindToRenderStep("desync_back", Enum.RenderPriority.First.Value, desync_back)
    else
        State.desync_con:Disconnect()
        Services.run_service:UnbindFromRenderStep("desync_back")
        desync_back()
    end
end

--[[ ragebot ]]

local function rage_step()
    local part = get_target()
    State.target = part
    if not part or not is_alive(State.character) then return end

    local cam = State.camera
    cam.CFrame = CFrame.lookAt(cam.CFrame.Position, part.Position)

    local now = os.clock()
    if now - State.last_shot >= Constants.fire_delay then
        State.last_shot = now
        mouse1click()
    end
end

local function set_rage(on)
    if on == State.rage then return end
    State.rage = on

    if on then
        Services.run_service:BindToRenderStep("rage", Enum.RenderPriority.Camera.Value + 1, rage_step)
    else
        Services.run_service:UnbindFromRenderStep("rage")
        State.target = nil
    end

    refresh_desync()
end

local function set_void(on)
    if on == State.void then return end
    State.void = on
    refresh_desync()
end

--[[ connect to gui ]]

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() LPH_ATTRIBUTES(VM(NONE))
    State.camera = workspace.CurrentCamera
end)

Services.local_player.CharacterAdded:Connect(on_char)
if Services.local_player.Character then
    on_char(Services.local_player.Character)
end

Services.user_input.InputBegan:Connect(function(input, processed) LPH_ATTRIBUTES(VM(NONE))
    if processed then return end

    local key = input.KeyCode
    if key == Constants.rage_key then
        set_rage(not State.rage)
    elseif key == Constants.void_key then
        set_void(not State.void)
    end
end)
