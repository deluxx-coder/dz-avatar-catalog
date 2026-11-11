--[[
    DZ AVATAR CATALOG ULTIMATE
    Brand: DZ / DELUX ZEPHYR
    Dasar logic: CRSZ x DZ | Evade Test Menu (deteksi rig Evade, Korblox, Headless, katalog, re-apply)

    SEMUA BERSIFAT VISUAL & LOKAL:
    - Tidak mengubah inventory / kepemilikan akun, tidak membeli, tidak memberi Limited gratis.
    - Perubahan tidak otomatis terlihat pemain lain.
    - Favorit / preset / posisi disimpan lewat writefile bila executor mendukung,
      kalau tidak hanya bertahan selama sesi (_G).
]]
if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local AES = game:GetService("AvatarEditorService")
local player = Players.LocalPlayer

if _G.DZ_CATALOG_CLEAN then pcall(_G.DZ_CATALOG_CLEAN) end
if _G.CRSZ_EVADE_CLEAN then pcall(_G.CRSZ_EVADE_CLEAN) end

local DZ = {Storage = {}, S = {}, Fav = {}, Pos = {}, Prev = {}, UI = {}, Status = {}, Cat = {}}
local S = DZ.S
S.alive = true
S.worn = {}
S.entries = {}
S.loading = {}
S.flags = {headless = false, korblox = false, korbloxL = false}
S.orig = setmetatable({}, {__mode = "k"})
S.bases = setmetatable({}, {__mode = "k"})
S.posCfg = {}
S.wearSeq = 0

local conns = {}
local function connect(sig, fn)
    local c = sig:Connect(fn)
    conns[#conns + 1] = c
    return c
end
DZ.connect = connect

local TAG = "CRSZ_"
DZ.log = function() end
DZ.repaint = function() end

-- ================= STORAGE (lokal) =================
do
    local St = DZ.Storage
    local DIR = "DZ_AvatarCatalog"
    local canFS = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
    St.canFS = canFS
    _G.DZ_CATALOG_MEM = _G.DZ_CATALOG_MEM or {}
    local mem = _G.DZ_CATALOG_MEM

    function St.load(name, default)
        if canFS then
            local ok, data = pcall(function()
                local path = DIR .. "/" .. name .. ".json"
                if isfile(path) then return HttpService:JSONDecode(readfile(path)) end
            end)
            if ok and data ~= nil then return data end
        elseif mem[name] ~= nil then
            return mem[name]
        end
        return default
    end

    function St.save(name, data)
        mem[name] = data
        if canFS then
            pcall(function()
                if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(DIR) then
                    makefolder(DIR)
                end
                writefile(DIR .. "/" .. name .. ".json", HttpService:JSONEncode(data))
            end)
        end
    end
end

S.settings = DZ.Storage.load("settings", {})
if type(S.settings) ~= "table" then S.settings = {} end
if S.settings.reapply == nil then S.settings.reapply = true end
if S.settings.replaceSlot == nil then S.settings.replaceSlot = true end

S.history = DZ.Storage.load("history", {})
if type(S.history) ~= "table" then S.history = {} end

DZ.savedPos = DZ.Storage.load("positions", {})
if type(DZ.savedPos) ~= "table" then DZ.savedPos = {} end

DZ.presets = DZ.Storage.load("presets", {})
if type(DZ.presets) ~= "table" then DZ.presets = {} end

-- ================= DETEKSI KARAKTER & RIG EVADE (dari DZ) =================
-- Evade menyimpan model pemain di Workspace.Rigs / Players / PlayerCache / Game.Players.
local function allChars(plr)
    local list, seen = {}, {}
    if not plr then return list end
    local function add(m)
        if m and m:IsA("Model") and m.Parent and not seen[m] and m:FindFirstChild("Head") then
            seen[m] = true
            table.insert(list, m)
        end
    end
    local function addAll(folder)
        if not folder then return end
        for _, ch in ipairs(folder:GetChildren()) do
            if ch.Name == plr.Name then add(ch) end
        end
    end
    addAll(workspace:FindFirstChild("Rigs"))
    addAll(workspace:FindFirstChild("Players"))
    addAll(workspace:FindFirstChild("PlayerCache"))
    local gm = workspace:FindFirstChild("Game")
    addAll(gm and gm:FindFirstChild("Players"))
    add(plr.Character)
    add(workspace:FindFirstChild(plr.Name))
    if #list == 0 then
        for _, f in ipairs(workspace:GetChildren()) do
            if f:IsA("Folder") or f:IsA("Model") then
                local c = f:FindFirstChild(plr.Name)
                if c then add(c) end
            end
        end
    end
    return list
end

local function rigOf(char)
    if not char then return nil end
    if not char:FindFirstChild("Head") then return nil end
    if char:FindFirstChild("UpperTorso") then return "R15" end
    return "R6"
end
DZ.allChars = allChars
DZ.rigOf = rigOf

-- deteksi struktur (Humanoid / part / Torso), untuk tampilan status saja
function DZ.rigDetail(char)
    if not char then return "?" end
    local t = rigOf(char) or "?"
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() t = (hum.RigType == Enum.HumanoidRigType.R15) and "R15" or "R6" end)
    end
    if not (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) then t = "Custom" end
    return t
end

-- Korblox kiri boleh di R6 & R15 (Evade bisa ganti bentuk)
local st = {}
st.leftR15 = function() return true end

-- ================= KORBLOX (logic DZ, tidak diubah) =================
local ID_KORBLOX_R, ID_KORBLOX_L = 139607718, 139607673
local buildKB = (function()

local KORBLOX_ASSET = ID_KORBLOX_R
local KORBLOX_ASSET_L = ID_KORBLOX_L
local MESH_URL = "rbxassetid://902942093"
local TEXTURE_URL = "rbxassetid://902843398"
local R6_LEG_MESH = "rbxassetid://101851696"
local R6_LEG_TEX = "rbxassetid://101851254"
local camParent = false

local R6_FIT = 1   -- tinggi kaki rakitan R6 (khusus kaki yang tidak punya mesh R6 bawaan)
local R6_Y = 0.1   -- geser vertikal kaki rakitan R6
local KORBLOX_R_SCALE = 0.8  -- UKURAN KORBLOX KANAN (1 = normal, 0.8 = lebih kecil, 0.6 = jauh lebih kecil)
local R15_Y = 0    -- geser vertikal part R15 (0 = persis posisi attachment asli)

local function norm(s) return ((s or ""):lower():gsub("[%s_]", "")) end

local function slotOf(name)
    local n = norm(name)
    if n:find("upperleg", 1, true) then return "U" end
    if n:find("lowerleg", 1, true) then return "L" end
    if n:find("foot", 1, true) then return "F" end
end

local function attOf(part, name)
    for _, c in ipairs(part:GetChildren()) do
        if c:IsA("Attachment") and norm(c.Name) == name then return c end
    end
end

local function strip(p)
    for _, c in ipairs(p:GetChildren()) do
        if c:IsA("Attachment") or c:IsA("WrapTarget") or c:IsA("WrapLayer") or c:IsA("JointInstance")
            or c:IsA("Constraint") or c:IsA("BaseScript") or c:IsA("Sound") then
            pcall(function() c:Destroy() end)
        end
    end
end

local function prep(p)
    p.Anchored = false
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.Massless = true
    p.Transparency = 0
end

local function weld(a, b)
    local w = Instance.new("WeldConstraint")
    w.Part0 = a
    w.Part1 = b
    w.Parent = b
end

local function make(cfg)
    local SIDE = cfg.side              -- "Right" | "Left"
    local sd = SIDE:lower()            -- "right" | "left"
    local FAKE, MESHN = cfg.fake, cfg.meshName
    local ASSET = cfg.asset
    local SC = cfg.scale or 1   -- skala ukuran kaki
    local JOINT = {
        U = {sd .. "hiprigattachment", sd .. "kneerigattachment"},
        L = {sd .. "kneerigattachment", sd .. "anklerigattachment"},
        F = {sd .. "anklerigattachment", sd .. "footattachment"},
    }
    local HIDE = cfg.hide or {}           -- slot yang tidak dipasang tapi tetap dipakai untuk ukuran (R6)
    local tplAll = {}
    local tpl, rel, tplAtt = {}, {}, {}   -- template MeshPart, posisi relatif ke paha, attachment asli tiap part
    local M6, T6 = cfg.r6Mesh, cfg.r6Tex  -- mesh R6
    local state, failedAt = "idle", 0     -- idle | loading | done | failed
    local waiting, fakeStore, H = {}, {}, {}

    local opp = (sd == "left") and "right" or "left"
    local SKIP = cfg.skip or {}   -- slot yang dibuang (mis. F = part kaki paling bawah)

    -- 1 = nama part sisi ini, -1 = sisi lawan, 0 = netral
    local function sideOf(d)
        local n = norm(d.Name)
        if n:find(sd, 1, true) then return 1 end
        if n:find(opp, 1, true) then return -1 end
        return 0
    end

    local function scan(root)
        local found, firstAny = {}, nil
        -- utamakan part yang namanya sesuai sisi; baru netral; terakhir apa saja
        for _, minSide in ipairs({1, 0, -1}) do
            found, firstAny = {}, nil
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("MeshPart") and d.MeshId ~= "" and sideOf(d) >= minSide then
                    local k = slotOf(d.Name)
                    if k and not found[k] then found[k] = d end
                    if not firstAny then firstAny = d end
                end
            end
            if next(found) or firstAny then break end
        end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("SpecialMesh") and d.MeshId ~= "" then
                if norm(d.Parent and d.Parent.Name) == sd .. "leg" and not M6 then
                    M6, T6 = d.MeshId, d.TextureId
                end
            end
        end
        if not found.U and firstAny and not (found.L or found.F) then found.U = firstAny end
        for k in pairs(SKIP) do found[k] = nil end
        local U, L, F = found.U, found.L, found.F
        if not (U or L or F) then return end
        local anchorK = U and "U" or (L and "L" or "F")

        rel[anchorK] = CFrame.new()
        if U and L then
            local ua, la = attOf(U, sd .. "kneerigattachment"), attOf(L, sd .. "kneerigattachment")
            if ua and la then rel.L = ua.CFrame * la.CFrame:Inverse()
            else rel.L = CFrame.new(0, -(U.Size.Y + L.Size.Y) / 2, 0) end
        end
        if L and F then
            local la, fa = attOf(L, sd .. "anklerigattachment"), attOf(F, sd .. "anklerigattachment")
            local lrel = rel.L or CFrame.new()
            if la and fa then rel.F = lrel * la.CFrame * fa.CFrame:Inverse()
            else rel.F = lrel * CFrame.new(0, -(L.Size.Y + F.Size.Y) / 2, 0) end
        elseif U and F then
            rel.F = CFrame.new(0, -(U.Size.Y + F.Size.Y) / 2, 0)
        end

        for k, p in pairs(found) do
            tplAtt[k] = {}
            for _, a in ipairs(p:GetChildren()) do
                if a:IsA("Attachment") then tplAtt[k][norm(a.Name)] = a.CFrame end
            end
            local c = p:Clone()
            strip(c)
            c.Parent = nil
            tplAll[k] = c
            if not HIDE[k] then tpl[k] = c end
        end
    end

    local function ensureLoad()
        if state == "loading" or state == "done" then return end
        if state == "failed" and os.clock() - failedAt < 5 then return end
        state = "loading"
        task.spawn(function()
            local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. ASSET) end)
            if ok and type(objs) == "table" then
                for _, o in ipairs(objs) do pcall(scan, o) end
            end
            if next(tpl) or (M6 and not cfg.r6Mesh) then
                state = "done"
                for c in pairs(waiting) do
                    waiting[c] = nil
                    if c.Parent then pcall(H.apply, c) end
                end
            else
                state = "failed"
                failedAt = os.clock()
            end
        end)
    end

    local function findLeg(char)
        local l6 = char:FindFirstChild(SIDE .. " Leg") or char:FindFirstChild(SIDE .. "Leg")
        if l6 and l6:IsA("BasePart") then return l6, {l6} end
        local u = char:FindFirstChild(SIDE .. "UpperLeg")
        local l = char:FindFirstChild(SIDE .. "LowerLeg")
        local f = char:FindFirstChild(SIDE .. "Foot")
        if u and l and f then return u, {u, l, f} end
        for _, p in ipairs(char:GetChildren()) do
            if p:IsA("BasePart") then
                local n = norm(p.Name)
                if n:find(sd, 1, true) and n:find("leg", 1, true) then return p, {p} end
            end
        end
    end

    local function getFake(char)
        local rec = fakeStore[char]
        if rec and rec.Parent then return rec end
        local f = char:FindFirstChild(FAKE)
        if f then return f end
        local cam = workspace.CurrentCamera
        return cam and cam:FindFirstChild(FAKE .. "_" .. char.Name)
    end

    local function sweepStore()
        for c, f in pairs(fakeStore) do
            if not c.Parent then
                pcall(function() f:Destroy() end)
                fakeStore[c] = nil
            end
        end
    end

    -- R6: ubah langsung SpecialMesh di kaki
    local function applyR6Leg(leg)
        local mesh = leg:FindFirstChild(MESHN) or leg:FindFirstChildOfClass("SpecialMesh")
        if not mesh then
            mesh = Instance.new("SpecialMesh")
            mesh.Name = MESHN
            mesh.MeshType = Enum.MeshType.FileMesh
            mesh.Parent = leg
        end
        -- kalau sudah ada mesh bawaan, simpan nilai aslinya supaya bisa dikembalikan
        if mesh.Name ~= MESHN and mesh:GetAttribute("DLX_oM") == nil then
            mesh:SetAttribute("DLX_oM", mesh.MeshId)
            mesh:SetAttribute("DLX_oT", mesh.TextureId)
            mesh:SetAttribute("DLX_oS", mesh.Scale)
        end
        if mesh.MeshId ~= M6 then mesh.MeshId = M6 end
        if mesh.TextureId ~= T6 then mesh.TextureId = T6 end
        local sc = mesh.Scale
        if sc.X ~= SC or sc.Y ~= SC or sc.Z ~= SC then mesh.Scale = Vector3.new(SC, SC, SC) end
        if leg.Transparency ~= 0 then leg.Transparency = 0 end
    end

    local function removeR6Leg(leg)
        local mine = leg:FindFirstChild(MESHN)
        if mine then mine:Destroy() end
        local m = leg:FindFirstChildOfClass("SpecialMesh")
        if m and m:GetAttribute("DLX_oM") ~= nil then
            m.MeshId = m:GetAttribute("DLX_oM")
            m.TextureId = m:GetAttribute("DLX_oT") or ""
            m.Scale = m:GetAttribute("DLX_oS") or Vector3.new(1, 1, 1)
            m:SetAttribute("DLX_oM", nil)
            m:SetAttribute("DLX_oT", nil)
            m:SetAttribute("DLX_oS", nil)
        end
        leg.Transparency = 0
    end

    -- hapus sisa fake (duplikat) milik sisi ini di karakter / kamera
    local function clearStray(char)
        for _, c in ipairs(char:GetChildren()) do
            if c.Name == FAKE then pcall(function() c:Destroy() end) end
        end
        local cam = workspace.CurrentCamera
        local f = cam and cam:FindFirstChild(FAKE .. "_" .. char.Name)
        if f then pcall(function() f:Destroy() end) end
    end

    local function place(char, obj)
        local cam = workspace.CurrentCamera
        if camParent and cam then
            obj.Name = FAKE .. "_" .. char.Name
            obj.Parent = cam
        else
            obj.Parent = char
        end
    end

    -- Tempatkan part asset seperti Roblox memasang body part asli:
    -- titik sambungan (attachment) part asset disejajarkan dengan titik yang sama di limb karakter.
    local function alignCF(limb, k)
        local ta = tplAtt[k]
        if ta then
            for _, nm in ipairs(JOINT[k]) do
                local la = attOf(limb, nm)
                if la and ta[nm] then
                    local a = ta[nm]
                    local sa = CFrame.new(a.Position * SC) * a.Rotation
                    return limb.CFrame * la.CFrame * sa:Inverse()
                end
            end
        end
        return limb.CFrame
    end

    local function fakeValid(old, char, tag)
        if old:GetAttribute("DLX_tag") ~= tag then return false end
        local n = 0
        for _, p in ipairs(old:GetChildren()) do
            local w = p:FindFirstChildOfClass("WeldConstraint")
            if not (w and w.Part0 and w.Part0:IsDescendantOf(char)) then return false end
            n = n + 1
        end
        return n > 0
    end

    -- cadangan (kaki kanan): satu part + SpecialMesh di atas limb, dipakai untuk R6 berkaki MeshPart
    -- atau R15 kalau asset gagal dimuat
    local function buildLegacy(char, base, hideParts, r6)
        for _, p in ipairs(hideParts) do
            if p.Transparency ~= 1 then p.Transparency = 1 end
        end
        local tag = r6 and "L6" or "L15"
        local old = getFake(char)
        if old and old.Parent then
            local w = old:FindFirstChildOfClass("WeldConstraint")
            if w and w.Part0 == base and old:GetAttribute("DLX_tag") == tag then return end
            old:Destroy()
        end
        clearStray(char)
        local leg = Instance.new("Part")
        leg.Name = FAKE
        leg.Size = base.Size
        leg.CanCollide = false
        leg.CanTouch = false
        leg.CanQuery = false
        leg.Massless = true
        leg.Transparency = 0
        leg.Material = Enum.Material.SmoothPlastic
        leg.Color = Color3.fromRGB(64, 64, 64)
        leg.CFrame = base.CFrame
        leg:SetAttribute("DLX_tag", tag)
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.FileMesh
        mesh.MeshId = r6 and cfg.r6Mesh or cfg.r15Mesh
        mesh.TextureId = r6 and cfg.r6Tex or cfg.r15Tex
        mesh.VertexColor = Vector3.new(1, 1, 1)
        mesh.Scale = Vector3.new(SC, SC, SC)
        mesh.Offset = Vector3.new(0, (1 - SC) * base.Size.Y / 2, 0)
        mesh.Parent = leg
        weld(base, leg)
        sweepStore()
        fakeStore[char] = leg
        place(char, leg)
    end

    local function buildFake(char, base, hideParts)
        for _, p in ipairs(hideParts) do
            if p.Transparency ~= 1 then p.Transparency = 1 end
        end
        local useLimbs = (#hideParts == 3)
        if not useLimbs and #hideParts == 1 then pcall(removeR6Leg, hideParts[1]) end
        for _, p in ipairs(hideParts) do
            if p.Transparency ~= 1 then p.Transparency = 1 end
        end
        local tag = (useLimbs and "R15" or "R6") .. "v6_" .. SIDE .. "_" .. tostring(SC)

        local old = getFake(char)
        if old and old.Parent then
            if fakeValid(old, char, tag) then return end
            old:Destroy()
        end

        clearStray(char)
        local folder = Instance.new("Folder")
        folder.Name = FAKE
        folder:SetAttribute("DLX_tag", tag)

        if useLimbs then
            local limbs = {U = hideParts[1], L = hideParts[2], F = hideParts[3]}
            for k, t in pairs(tpl) do
                local limb = limbs[k]
                if limb then
                    local p = t:Clone()
                    prep(p)
                    p.Size = t.Size * SC
                    p.CFrame = alignCF(limb, k) * CFrame.new(0, R15_Y, 0)
                    weld(limb, p)
                    p.Parent = folder
                end
            end
        else
            -- R6: rakit semua part lalu skalakan supaya pas dengan kaki
            local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
            for k, t in pairs(tplAll) do
                local pos, sz = (rel[k] or CFrame.new()).Position, t.Size
                minX = math.min(minX, pos.X - sz.X / 2); maxX = math.max(maxX, pos.X + sz.X / 2)
                minY = math.min(minY, pos.Y - sz.Y / 2); maxY = math.max(maxY, pos.Y + sz.Y / 2)
                minZ = math.min(minZ, pos.Z - sz.Z / 2); maxZ = math.max(maxZ, pos.Z + sz.Z / 2)
            end
            local height = math.max(maxY - minY, 0.1)
            local s = (base.Size.Y / height) * R6_FIT * SC
            local center = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
            for k, t in pairs(tpl) do
                local r = rel[k] or CFrame.new()
                local p = t:Clone()
                prep(p)
                p.Size = t.Size * s
                p.CFrame = base.CFrame * CFrame.new(0, R6_Y + (1 - SC) * base.Size.Y * R6_FIT / 2, 0) * CFrame.new((r.Position - center) * s)
                weld(base, p)
                p.Parent = folder
            end
        end

        if #folder:GetChildren() == 0 then
            folder:Destroy()
            return
        end
        sweepStore()
        fakeStore[char] = folder
        place(char, folder)
    end

    H.apply = function(char)
        if not char then return end
        local base, hide = findLeg(char)
        if not base then return end
        local r6 = (rigOf(char) == "R6")

        -- kaki kiri hanya untuk R6 (kecuali di game katalog avatar)
        if cfg.r15Ok and not r6 and not cfg.r15Ok() then
            H.remove(char)
            return
        end

        -- mode rakitan part (R6 tanpa bulet kaki): dipakai kalau asset sudah siap
        local partsMode = cfg.r6Parts and next(tpl) ~= nil

        -- R6 dengan kaki biasa + mesh R6 sudah diketahui -> ganti mesh langsung
        if r6 and not partsMode and M6 and #hide == 1 and not base:IsA("MeshPart") then
            local fake = getFake(char)
            if fake then pcall(function() fake:Destroy() end) fakeStore[char] = nil end
            applyR6Leg(base)
            return
        end
        -- R6 berkaki MeshPart (kaki kanan): part palsu + mesh R6 bawaan
        if r6 and not partsMode and cfg.r6Mesh then
            buildLegacy(char, base, hide, true)
            return
        end

        -- selebihnya (R15 / R6 rakitan) butuh part dari asset
        if state == "idle" or state == "loading" then
            waiting[char] = true
            ensureLoad()
            return
        end
        if state == "failed" then ensureLoad() end
        if next(tpl) then
            buildFake(char, base, hide)
        elseif cfg.r15Mesh and not r6 then
            buildLegacy(char, base, hide, false)
        end
    end

    local function remove(char)
        if not char then return end
        waiting[char] = nil
        local fake = getFake(char)
        if fake then pcall(function() fake:Destroy() end) end
        fakeStore[char] = nil
        local r6leg = char:FindFirstChild(SIDE .. " Leg") or char:FindFirstChild(SIDE .. "Leg")
        if r6leg and r6leg:IsA("BasePart") then pcall(removeR6Leg, r6leg) end
        for _, n in ipairs({SIDE .. "UpperLeg", SIDE .. "LowerLeg", SIDE .. "Foot", SIDE .. " Leg", SIDE .. "Leg"}) do
            local p = char:FindFirstChild(n)
            if p and p.Transparency ~= 0 then p.Transparency = 0 end
        end
    end

    H.remove = remove
    ensureLoad() -- muat asset dari awal supaya langsung siap saat toggle dinyalakan
    return H.apply, remove
end

local applyR, removeR = make({
    side = "Right", fake = "FakeKorblox", meshName = "DLX_KorbloxMesh", asset = KORBLOX_ASSET,
    r6Mesh = R6_LEG_MESH, r6Tex = R6_LEG_TEX, r15Mesh = MESH_URL, r15Tex = TEXTURE_URL,
    skip = {F = true}, hide = {L = true}, r6Parts = true, scale = KORBLOX_R_SCALE,
})
local applyL, removeL = make({
    side = "Left", fake = "FakeKorbloxL", meshName = "DLX_KorbloxMeshL", asset = KORBLOX_ASSET_L, skip = {F = true}, r15Ok = st.leftR15,
})
return {applyR = applyR, removeR = removeR, applyL = applyL, removeL = removeL}
end)

-- KB dibangun malas: asset Korblox baru diunduh saat benar-benar dipakai
local KBreal
local function kbGet()
    if not KBreal then KBreal = buildKB() end
    return KBreal
end
local KB = {
    applyR = function(c) return kbGet().applyR(c) end,
    applyL = function(c) return kbGet().applyL(c) end,
    removeR = function(c) if KBreal then return KBreal.removeR(c) end end,
    removeL = function(c) if KBreal then return KBreal.removeL(c) end end,
}

-- ================= HEADLESS (dari DZ) =================
local function setHeadOn(char, visible)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    local want = visible and 0 or 1
    if head.Transparency ~= want then head.Transparency = want end
    for _, v in ipairs(head:GetChildren()) do
        if v:IsA("Decal") and v.Transparency ~= want then v.Transparency = want end
    end
end

-- =====================================================================
-- ================= TARGET: SAYA & FRIEND =============================
-- Saya   : perubahan langsung terlihat di karakter sendiri (visual lokal).
-- Friend : tiap slot punya DRAFT sendiri. Draft hanya dipratinjau di panel
--          preview; baru dipasang ke karakter teman setelah tombol APPLY.
-- =====================================================================
local P = DZ.Pos
local R15 = {
    Head = true, UpperTorso = true, LowerTorso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}
DZ.R15 = R15

local function newTarget(kind, plr)
    local t = {
        kind = kind, plr = plr, userId = plr and plr.UserId or nil,
        name = plr and plr.Name or "?", display = plr and plr.DisplayName or "?",
        worn = {}, flags = {headless = false, korblox = false, korbloxL = false},
        posCfg = {}, orig = setmetatable({}, {__mode = "k"}), ord = {}, seq = 0, dirty = false,
    }
    if kind == "me" then
        t.live, t.liveFlags, t.liveCfg = t.worn, t.flags, t.posCfg -- Saya: draft = live
    else
        t.live, t.liveFlags, t.liveCfg = {}, {headless = false, korblox = false, korbloxL = false}, {}
    end
    return t
end

DZ.me = newTarget("me", player)
DZ.cur = DZ.me
S.worn, S.flags, S.posCfg, S.orig = DZ.me.worn, DZ.me.flags, DZ.me.posCfg, DZ.me.orig

local function plrOf(t)
    if t.kind == "me" then return player end
    local p = t.userId and Players:GetPlayerByUserId(t.userId) or nil
    t.plr = p
    return p
end
DZ.plrOf = plrOf

function DZ.curChar()
    local p = plrOf(DZ.cur)
    return p and allChars(p)[1] or nil
end

function DZ.targetLabel(t)
    if t.kind == "me" then return "SAYA" end
    for i, s in ipairs(DZ.slots or {}) do
        if s.t == t then return "FRIEND " .. i .. " | " .. tostring(t.display) end
    end
    return tostring(t.display)
end

-- ================= EDITOR POSISI: konfigurasi per item =================
do
    P.sel = nil
    P.KEYS = {"px", "py", "pz", "rx", "ry", "rz", "sx", "sy", "sz"}
    P.RANGE = {
        px = {-5, 5, 0.01}, py = {-5, 5, 0.01}, pz = {-5, 5, 0.01},
        rx = {-180, 180, 1}, ry = {-180, 180, 1}, rz = {-180, 180, 1},
        sx = {0.05, 5, 0.01}, sy = {0.05, 5, 0.01}, sz = {0.05, 5, 0.01},
        su = {0.05, 5, 0.01},
    }

    local function defaults()
        return {px = 0, py = 0, pz = 0, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1}
    end

    function P.cfgIn(tbl, id)
        local c = tbl[id]
        if not c then
            c = defaults()
            local sv = DZ.savedPos[tostring(id)]
            if type(sv) == "table" then
                for _, k in ipairs(P.KEYS) do
                    if type(sv[k]) == "number" then c[k] = sv[k] end
                end
            end
            tbl[id] = c
        end
        return c
    end

    function P.cfg(id) return P.cfgIn(S.posCfg, id) end

    function P.copy(id)
        local c, out = P.cfg(id), {}
        for _, k in ipairs(P.KEYS) do out[k] = c[k] end
        return out
    end

    function P.applyTransform(model)
        local b = S.bases[model]
        if not b or not b.handle or not b.handle.Parent or not b.weld.Parent then return end
        local c = b.cfg
        local sc = Vector3.new(c.sx, c.sy, c.sz)
        if b.mesh then
            b.mesh.Scale = b.meshScale * sc
        else
            b.handle.Size = b.size * sc
        end
        -- Z positif = depan (depan karakter = -Z lokal)
        b.weld.C0 = CFrame.new(c.px, c.py, -c.pz) * b.c0 * CFrame.Angles(math.rad(c.rx), math.rad(c.ry), math.rad(c.rz))
        b.weld.C1 = CFrame.new(b.c1.Position * sc) * b.c1.Rotation
        if b.preview and b.weld.Part0 then
            b.handle.CFrame = b.weld.Part0.CFrame * b.weld.C0 * b.weld.C1:Inverse()
        end
    end

    function P.refresh(id)
        local t = DZ.cur
        if t.kind == "me" then
            local ch = allChars(player)[1]
            local m = ch and ch:FindFirstChild(TAG .. id)
            if m then P.applyTransform(m) end
        else
            t.dirty = true
        end
        DZ.Prev.dirty = true
        if DZ.UI.edRefresh then DZ.UI.edRefresh() end
        if DZ.UI.bannerUpdate then DZ.UI.bannerUpdate() end
    end

    function P.set(key, v)
        local id = P.sel
        if not id or not S.worn[id] or S.worn[id].kind ~= "Acc" then return end
        local r = P.RANGE[key]
        if not r or type(v) ~= "number" then return end
        v = math.clamp(math.floor(v / r[3] + 0.5) * r[3], r[1], r[2])
        local c = P.cfg(id)
        if key == "su" then
            c.sx, c.sy, c.sz = v, v, v
        else
            c[key] = v
        end
        P.refresh(id)
    end

    function P.get(key)
        local id = P.sel
        if not id then return 0 end
        local c = P.cfg(id)
        if key == "su" then return c.sy end
        return c[key]
    end

    function P.reset(which)
        local id = P.sel
        if not id or not S.worn[id] then return end
        local c = P.cfg(id)
        if which == "pos" or which == "all" then c.px, c.py, c.pz = 0, 0, 0 end
        if which == "rot" or which == "all" then c.rx, c.ry, c.rz = 0, 0, 0 end
        if which == "scale" or which == "all" then c.sx, c.sy, c.sz = 1, 1, 1 end
        P.refresh(id)
    end

    function P.save()
        local id = P.sel
        if not id or not S.worn[id] then return false end
        DZ.savedPos[tostring(id)] = P.copy(id)
        DZ.Storage.save("positions", DZ.savedPos)
        return true
    end

    function P.restore()
        local id = P.sel
        if not id or not S.worn[id] then return false end
        local sv = DZ.savedPos[tostring(id)]
        if type(sv) ~= "table" then return false end
        local c = P.cfg(id) -- diubah di tempat supaya model yang sudah terpasang ikut berubah
        for _, k in ipairs(P.KEYS) do
            if type(sv[k]) == "number" then c[k] = sv[k] end
        end
        P.refresh(id)
        return true
    end

    function P.select(id)
        local e = id and S.worn[id]
        if e and e.kind == "Acc" then P.sel = id else P.sel = nil end
        if DZ.UI.edChips then DZ.UI.edChips() end
        if DZ.UI.edRefresh then DZ.UI.edRefresh() end
    end
end

-- ================= LOAD ASSET =================
local function loadEntry(id, name, cb)
    if S.entries[id] then cb(S.entries[id]) return end
    if S.loading[id] then table.insert(S.loading[id], cb) return end
    S.loading[id] = {cb}
    task.spawn(function()
        local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
        local e
        if ok and type(objs) == "table" then
            for _, o in ipairs(objs) do
                local sh = o:IsA("Shirt") and o or o:FindFirstChildWhichIsA("Shirt", true)
                local pa = o:IsA("Pants") and o or o:FindFirstChildWhichIsA("Pants", true)
                local tg = o:IsA("ShirtGraphic") and o or o:FindFirstChildWhichIsA("ShirtGraphic", true)
                local handle = (o:IsA("BasePart") and o.Name == "Handle" and o) or o:FindFirstChild("Handle", true)
                local dc = o:IsA("Decal") and o or o:FindFirstChildWhichIsA("Decal", true)
                -- body part (R15): part bernama anggota badan dan bukan Handle aksesori
                local bodyParts, nBody = {}, 0
                local cms, nCm = {}, 0
                if not handle then
                    local list = o:GetDescendants()
                    list[#list + 1] = o
                    for _, d in ipairs(list) do
                        if d:IsA("BasePart") and R15[d.Name] and not bodyParts[d.Name] then
                            bodyParts[d.Name] = d
                            nBody = nBody + 1
                        elseif d:IsA("CharacterMesh") then
                            -- body part klasik R6: CharacterMesh (BodyPart + MeshId + texture)
                            pcall(function()
                                local g = d.BodyPart.Name
                                local function url(n) return (n and n ~= 0) and ("rbxassetid://" .. tostring(n)) or "" end
                                if not cms[g] and d.MeshId ~= 0 then
                                    local tex = url(d.OverlayTextureId)
                                    if tex == "" then tex = url(d.BaseTextureId) end
                                    cms[g] = {mesh = url(d.MeshId), tex = tex}
                                    nCm = nCm + 1
                                end
                            end)
                        end
                    end
                end
                if sh then
                    e = {kind = "Shirt", tpl = sh.ShirtTemplate}
                elseif pa then
                    e = {kind = "Pants", tpl = pa.PantsTemplate}
                elseif tg then
                    e = {kind = "TShirt", tpl = tg.Graphic}
                elseif nBody > 0 or nCm > 0 then
                    local parts = {}
                    for pname, src in pairs(bodyParts) do
                        local atts = {}
                        for _, a in ipairs(src:GetChildren()) do
                            if a:IsA("Attachment") then atts[a.Name] = a.CFrame end
                        end
                        local c = src:Clone()
                        for _, ch in ipairs(c:GetChildren()) do
                            if ch:IsA("Attachment") or ch:IsA("WrapTarget") or ch:IsA("WrapLayer") or ch:IsA("JointInstance")
                                or ch:IsA("Constraint") or ch:IsA("LuaSourceContainer") or ch:IsA("Sound") or ch:IsA("Bone") then
                                pcall(function() ch:Destroy() end)
                            end
                        end
                        c.Parent = nil
                        parts[pname] = {part = c, atts = atts}
                    end
                    e = {kind = "Body", parts = parts, cm = cms}
                elseif handle then
                    local ap = CFrame.new()
                    local acc = handle:FindFirstAncestorWhichIsA("Accoutrement")
                    if acc then pcall(function() ap = acc.AttachmentPoint end) end
                    local layered = handle:FindFirstChildWhichIsA("WrapLayer", true) ~= nil
                    local clone = handle:Clone()
                    for _, d in ipairs(clone:GetDescendants()) do
                        if d:IsA("LuaSourceContainer") or d:IsA("Weld")
                            or d:IsA("WeldConstraint") or d:IsA("Motor6D") then
                            d:Destroy()
                        end
                    end
                    e = {kind = "Acc", handle = clone, ap = ap, layered = layered}
                elseif dc then
                    e = {kind = "Face", tpl = dc.Texture}
                end
                if e then break end
            end
        end
        local cbs = S.loading[id]
        S.loading[id] = nil
        if e then
            e.id = id
            e.name = name
            S.entries[id] = e
        end
        for _, f in ipairs(cbs or {}) do pcall(f, e) end
    end)
end
DZ.loadEntry = loadEntry

-- ================= PASANG KE MODEL (Evade: model dari allChars) =================
local function findAtt(parent, name)
    for _, c in ipairs(parent:GetChildren()) do
        if c.Name == name and c:IsA("Attachment") then return c end
    end
end

-- cfg = tabel posisi item ini (dipilih per target), preview = true untuk salinan di panel preview
local function attachAcc(char, id, e, cfg, preview)
    if char:FindFirstChild(TAG .. id) then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    local handle = e.handle:Clone()
    handle.Name = "Handle"
    handle.Anchored = false
    handle.CanCollide = false
    handle.CanTouch = false
    handle.CanQuery = false
    handle.Massless = true
    handle.Transparency = 0

    local part, charAtt, itemAtt
    for _, d in ipairs(handle:GetChildren()) do
        if d:IsA("Attachment") then
            for _, p in ipairs(char:GetChildren()) do
                if p:IsA("BasePart") then
                    local m = findAtt(p, d.Name)
                    if m then part, charAtt, itemAtt = p, m, d break end
                end
            end
            if part then break end
        end
    end

    local model = Instance.new("Model")
    model.Name = TAG .. id
    handle.Parent = model

    local weld = Instance.new("Weld")
    weld.Name = "CRSZ_Weld"
    local c0, c1
    if part then
        c0, c1 = charAtt.CFrame, itemAtt.CFrame
    else
        c0, c1 = CFrame.new(0, head.Size.Y / 2, 0) * e.ap:Inverse(), CFrame.new()
    end
    weld.Part0 = part or head
    weld.C0 = c0
    weld.C1 = c1
    weld.Part1 = handle
    weld.Parent = handle
    model.Parent = char

    local sm = handle:FindFirstChildOfClass("SpecialMesh")
    S.bases[model] = {
        handle = handle, weld = weld, c0 = c0, c1 = c1, size = handle.Size, cfg = cfg, preview = preview,
        mesh = sm, meshScale = sm and sm.Scale or Vector3.new(1, 1, 1),
    }
    P.applyTransform(model)
end

-- body part: overlay MeshPart di atas anggota badan R15 (anggota asli disembunyikan)
local function bodyPrep(p)
    p.Anchored = false
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.Massless = true
    p.Transparency = 0
end

local function setLimbHidden(limb, hidden)
    local want = hidden and 1 or 0
    if limb.Transparency ~= want then limb.Transparency = want end
    if limb.Name == "Head" then
        for _, d in ipairs(limb:GetChildren()) do
            if d:IsA("Decal") and d.Transparency ~= want then d.Transparency = want end
        end
    end
end

-- ===== BODY PART: R15 & R6 (overlay, anggota asli disembunyikan) =====
local LIMBS15 = {
    Head = {"Head"},
    Torso = {"UpperTorso", "LowerTorso"},
    LeftArm = {"LeftUpperArm", "LeftLowerArm", "LeftHand"},
    RightArm = {"RightUpperArm", "RightLowerArm", "RightHand"},
    LeftLeg = {"LeftUpperLeg", "LeftLowerLeg", "LeftFoot"},
    RightLeg = {"RightUpperLeg", "RightLowerLeg", "RightFoot"},
}
local LIMB6 = {
    Head = "Head", Torso = "Torso", LeftArm = "Left Arm", RightArm = "Right Arm",
    LeftLeg = "Left Leg", RightLeg = "Right Leg",
}
local GROUP_OF15 = {}
for g, list in pairs(LIMBS15) do
    for _, n in ipairs(list) do GROUP_OF15[n] = g end
end

-- grup badan yang disentuh sebuah entry Body (Head/Torso/LeftArm/...)
local function bodyGroups(e)
    if e.groups then return e.groups end
    local g = {}
    for pname in pairs(e.parts or {}) do
        local k = GROUP_OF15[pname]
        if k then g[k] = true end
    end
    for k in pairs(e.cm or {}) do g[k] = true end
    e.groups = g
    return g
end

-- cari anggota badan untuk satu grup; otomatis R15 atau R6 (rig Evade bisa campuran)
local function findLimbs(char, group)
    if char:FindFirstChild("UpperTorso") then
        local found, n = {}, 0
        for _, nm in ipairs(LIMBS15[group]) do
            local l = char:FindFirstChild(nm)
            if l and l:IsA("BasePart") then found[nm] = l n = n + 1 end
        end
        if n > 0 then return "R15", found end
    end
    local l6 = char:FindFirstChild(LIMB6[group])
    if l6 and l6:IsA("BasePart") then return "R6", {[LIMB6[group]] = l6} end
    return nil
end

local function charScale(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local function v(n)
        local o = hum and hum:FindFirstChild(n)
        if o and o:IsA("NumberValue") and o.Value > 0 then return o.Value end
        return 1
    end
    return Vector3.new(v("BodyWidthScale"), v("BodyHeightScale"), v("BodyDepthScale"))
end

-- susun rantai part R15 (UpperArm > LowerArm > Hand, LowerTorso > UpperTorso) lalu muat ke satu limb R6
local function chainSpecs(e, limb, names, joints, dir)
    local list, prev = {}, nil
    for i, nm in ipairs(names) do
        local rec = e.parts[nm]
        if rec then
            local sz = rec.part.Size
            local cf
            if not prev then
                cf = CFrame.new()
            else
                local jn = joints[i - 1]
                local a1 = (prev.name == names[i - 1] and jn) and prev.rec.atts[jn] or nil
                local a2 = jn and rec.atts[jn] or nil
                if a1 and a2 then
                    cf = prev.cf * a1 * a2:Inverse()
                else
                    cf = prev.cf * CFrame.new(0, dir * (prev.rec.part.Size.Y + sz.Y) / 2, 0)
                end
            end
            prev = {name = nm, rec = rec, cf = cf}
            list[#list + 1] = prev
        end
    end
    if #list == 0 then return {} end
    local top, bot = -math.huge, math.huge
    for _, it in ipairs(list) do
        local y, h = it.cf.Position.Y, it.rec.part.Size.Y / 2
        top = math.max(top, y + h)
        bot = math.min(bot, y - h)
    end
    local lh = limb.Size.Y
    local total = top - bot
    local f = total > 0.01 and math.clamp(lh / total, 0.5, 2) or 1
    local out = {}
    for _, it in ipairs(list) do
        local p, sz = it.cf.Position, it.rec.part.Size
        local y = lh / 2 + (p.Y - top) * f
        out[#out + 1] = {
            name = it.name, rec = it.rec, limb = limb,
            cf = limb.CFrame * CFrame.new(p.X, y, p.Z) * it.cf.Rotation,
            size = Vector3.new(sz.X, sz.Y * f, sz.Z),
        }
    end
    return out
end

local function buildSpecs(char, e, group, mode, limbs)
    local out = {}
    if mode == "R15" then
        local sc = charScale(char)
        for pname, limb in pairs(limbs) do
            local rec = e.parts and e.parts[pname]
            if rec then
                local cf = limb.CFrame
                for an, tcf in pairs(rec.atts) do
                    local la = findAtt(limb, an)
                    if la then
                        local t2 = CFrame.new(tcf.Position * sc) * tcf.Rotation
                        cf = limb.CFrame * la.CFrame * t2:Inverse()
                        break
                    end
                end
                out[#out + 1] = {name = pname, rec = rec, limb = limb, cf = cf, size = rec.part.Size * sc}
            end
        end
        return out
    end
    -- rig R6 (Torso / Left Arm / ... satu part per anggota)
    local _, limb = next(limbs)
    if not limb then return out end
    local cm = e.cm and e.cm[group]
    if cm then
        out[1] = {name = "CM_" .. group, limb = limb, cm = cm, cf = limb.CFrame, size = limb.Size}
    elseif e.parts and next(e.parts) then
        if group == "Head" then
            local rec = e.parts.Head
            if rec then
                local sz = rec.part.Size
                out[1] = {
                    name = "Head", rec = rec, limb = limb, size = sz,
                    cf = limb.CFrame * CFrame.new(0, (sz.Y - limb.Size.Y) / 2, 0),
                }
            end
        elseif group == "Torso" then
            out = chainSpecs(e, limb, {"LowerTorso", "UpperTorso"}, {"WaistRigAttachment"}, 1)
        else
            local side = group:sub(1, 1) == "L" and "Left" or "Right"
            if group:find("Arm") then
                out = chainSpecs(e, limb, {side .. "UpperArm", side .. "LowerArm", side .. "Hand"},
                    {side .. "ElbowRigAttachment", side .. "WristRigAttachment"}, -1)
            else
                out = chainSpecs(e, limb, {side .. "UpperLeg", side .. "LowerLeg", side .. "Foot"},
                    {side .. "KneeRigAttachment", side .. "AnkleRigAttachment"}, -1)
            end
        end
    end
    return out
end

local function makeOverlay(spec)
    local p
    if spec.cm then
        p = Instance.new("Part")
        p.Size = spec.limb.Size
        local sm = Instance.new("SpecialMesh")
        sm.MeshType = Enum.MeshType.FileMesh
        sm.MeshId = spec.cm.mesh
        sm.TextureId = spec.cm.tex or ""
        sm.Parent = p
        p.Color = spec.limb.Color
        p.Material = spec.limb.Material
    else
        p = spec.rec.part:Clone()
        p.Size = spec.size
        if p:IsA("MeshPart") and p.TextureID == "" and not p:FindFirstChildOfClass("SurfaceAppearance") then
            p.Color = spec.limb.Color
        end
    end
    p.Name = spec.name
    bodyPrep(p)
    p.CFrame = spec.cf
    if spec.limb.Name == "Head" and not p:FindFirstChildOfClass("Decal") then
        for _, d in ipairs(spec.limb:GetChildren()) do
            if d:IsA("Decal") then
                local c = d:Clone()
                c.Transparency = 0
                c.Parent = p
            end
        end
    end
    return p
end

local function applyBody(char, id, e)
    local fname = TAG .. "B" .. id
    local folder = char:FindFirstChild(fname)
    if folder then
        -- sudah terpasang: pastikan masih menempel ke anggota badan yang sama, kalau tidak bangun ulang
        local kids = folder:GetChildren()
        local ok = #kids > 0
        for _, p in ipairs(kids) do
            local w = p:FindFirstChildOfClass("WeldConstraint")
            if not (w and w.Part0 and w.Part0:IsDescendantOf(char)) then ok = false break end
        end
        if ok then
            for _, p in ipairs(kids) do
                setLimbHidden(p:FindFirstChildOfClass("WeldConstraint").Part0, true)
            end
            return
        end
        pcall(function() folder:Destroy() end)
    end

    local specs = {}
    for group in pairs(bodyGroups(e)) do
        local mode, limbs = findLimbs(char, group)
        if mode then
            for _, s in ipairs(buildSpecs(char, e, group, mode, limbs)) do specs[#specs + 1] = s end
        end
    end
    if #specs == 0 then
        e.warned = e.warned or setmetatable({}, {__mode = "k"})
        if not e.warned[char] then
            e.warned[char] = true
            if DZ.log then
                DZ.log("Body part '" .. tostring(e.name) .. "' tidak cocok dengan rig ini (asset R6 klasik tidak bisa di R15 murni).")
            end
        end
        return
    end

    folder = Instance.new("Folder")
    folder.Name = fname
    for _, s in ipairs(specs) do
        local okp, p = pcall(makeOverlay, s)
        if okp and p then
            local w = Instance.new("WeldConstraint")
            w.Part0 = s.limb
            w.Part1 = p
            w.Parent = p
            p.Parent = folder
            setLimbHidden(s.limb, true)
        end
    end
    folder.Parent = char
end

local function removeBody(char, id, e, headless)
    local f = char:FindFirstChild(TAG .. "B" .. id)
    if f then f:Destroy() end
    for group in pairs(bodyGroups(e)) do
        local names = {LIMB6[group]}
        for _, n in ipairs(LIMBS15[group]) do names[#names + 1] = n end
        for _, n in ipairs(names) do
            local limb = char:FindFirstChild(n)
            if limb and limb:IsA("BasePart") then
                setLimbHidden(limb, n == "Head" and headless == true)
            end
        end
    end
end
DZ.applyBody, DZ.attachAcc = applyBody, attachAcc

local function putCloth(char, cls, prop, tpl, orig)
    local rec = orig[char]
    if not rec then rec = {} orig[char] = rec end
    local inst = char:FindFirstChildOfClass(cls)
    if rec[cls] == nil then rec[cls] = inst and inst[prop] or false end
    if not inst then
        inst = Instance.new(cls)
        inst.Parent = char
    end
    if inst[prop] ~= tpl then inst[prop] = tpl end
end

local function restoreCloth(char, cls, prop, orig)
    local rec = orig[char]
    if not rec or rec[cls] == nil then return end
    local inst = char:FindFirstChildOfClass(cls)
    if inst then
        if rec[cls] == false then inst:Destroy() else inst[prop] = rec[cls] end
    end
    rec[cls] = nil
end

local function putFace(char, tpl, orig)
    local head = char:FindFirstChild("Head")
    local d = head and head:FindFirstChildOfClass("Decal")
    if not d then return end
    local rec = orig[char]
    if not rec then rec = {} orig[char] = rec end
    if rec.Face == nil then rec.Face = d.Texture end
    if d.Texture ~= tpl then d.Texture = tpl end
end

local function restoreFace(char, orig)
    local rec = orig[char]
    if not rec or rec.Face == nil then return end
    local head = char:FindFirstChild("Head")
    local d = head and head:FindFirstChildOfClass("Decal")
    if d then d.Texture = rec.Face end
    rec.Face = nil
end

-- pasang isi t.live (yang benar-benar tampil di dunia) ke karakter target
local function applyAll(t)
    t = t or DZ.me
    local plr = plrOf(t)
    if not plr then return end
    local chars = allChars(plr)
    local primary = chars[1]
    if not primary then return end
    local lf = t.liveFlags
    for _, c in ipairs(chars) do
        if lf.korblox then pcall(KB.applyR, c) end
        if lf.korbloxL then pcall(KB.applyL, c) end
        if lf.headless then pcall(setHeadOn, c, false) end
        for id, e in pairs(t.live) do
            if e.kind == "Shirt" then pcall(putCloth, c, "Shirt", "ShirtTemplate", e.tpl, t.orig)
            elseif e.kind == "Pants" then pcall(putCloth, c, "Pants", "PantsTemplate", e.tpl, t.orig)
            elseif e.kind == "TShirt" then pcall(putCloth, c, "ShirtGraphic", "Graphic", e.tpl, t.orig)
            elseif e.kind == "Face" then pcall(putFace, c, e.tpl, t.orig)
            elseif e.kind == "Body" then pcall(applyBody, c, id, e) end
        end
    end
    for id, e in pairs(t.live) do
        if e.kind == "Acc" then
            pcall(attachAcc, primary, id, e, P.cfgIn(t.liveCfg, id), false)
        end
    end
end
DZ.applyAll = applyAll

local function worldRemove(t, id, e)
    local plr = plrOf(t)
    if not plr then return end
    for _, c in ipairs(allChars(plr)) do
        if e.kind == "Acc" then
            local m = c:FindFirstChild(TAG .. id)
            if m then m:Destroy() end
        elseif e.kind == "Body" then pcall(removeBody, c, id, e, t.liveFlags.headless)
        elseif e.kind == "Shirt" then pcall(restoreCloth, c, "Shirt", "ShirtTemplate", t.orig)
        elseif e.kind == "Pants" then pcall(restoreCloth, c, "Pants", "PantsTemplate", t.orig)
        elseif e.kind == "TShirt" then pcall(restoreCloth, c, "ShirtGraphic", "Graphic", t.orig)
        elseif e.kind == "Face" then pcall(restoreFace, c, t.orig) end
    end
end

local function worldFlagsOff(t)
    local plr = plrOf(t)
    if not plr then return end
    for _, c in ipairs(allChars(plr)) do
        pcall(KB.removeR, c)
        pcall(KB.removeL, c)
        pcall(setHeadOn, c, true)
    end
end

-- ================= WEAR / UNWEAR (pada target yang sedang diedit) =================
local SLOT_EXCLUSIVE = {Hair = true, Neck = true, Face = true, Shoulder = true, Front = true, Back = true, Waist = true}

function DZ.wornList()
    local ord = DZ.cur.ord
    local list = {}
    for _, e in pairs(S.worn) do list[#list + 1] = e end
    table.sort(list, function(a, b) return (ord[a.id] or 0) > (ord[b.id] or 0) end)
    return list
end

function DZ.wornItems()
    local out = {}
    for _, e in ipairs(DZ.wornList()) do
        out[#out + 1] = {id = e.id, name = e.name, cat = e.cat, group = e.group, slot = e.slot}
    end
    return out
end

local function addHistory(item)
    for i, h in ipairs(S.history) do
        if h.id == item.id then table.remove(S.history, i) break end
    end
    table.insert(S.history, 1, {id = item.id, name = item.name, cat = item.cat, group = item.group, slot = item.slot})
    while #S.history > 60 do table.remove(S.history) end
    DZ.Storage.save("history", S.history)
end

function DZ.unwear(id)
    local t = DZ.cur
    local e = S.worn[id]
    if not e then return end
    S.worn[id] = nil
    if t.kind == "me" then worldRemove(t, id, e) else t.dirty = true end
    if P.sel == id then
        P.sel = nil
        for _, o in ipairs(DZ.wornList()) do
            if o.kind == "Acc" then P.sel = o.id break end
        end
    end
    DZ.Prev.dirty = true
end

function DZ.wear(e, item, keepOthers)
    local t = DZ.cur
    item = item or {}
    e.name = item.name or e.name
    e.cat = item.cat or e.cat or "Item"
    e.slot = item.slot or e.slot
    e.group = item.group or e.group or "GEN"
    if e.kind == "Acc" then
        if S.settings.replaceSlot and not keepOthers and e.slot and SLOT_EXCLUSIVE[e.slot] then
            for oid, oe in pairs(S.worn) do
                if oid ~= e.id and oe.kind == "Acc" and oe.slot == e.slot then DZ.unwear(oid) end
            end
        end
    elseif e.kind == "Body" then
        for oid, oe in pairs(S.worn) do
            if oid ~= e.id and oe.kind == "Body" then
                local overlap = false
                local gb = bodyGroups(oe)
                for g in pairs(bodyGroups(e)) do if gb[g] then overlap = true end end
                if overlap then DZ.unwear(oid) end
            end
        end
    else
        for oid, oe in pairs(S.worn) do
            if oe.kind == e.kind and oid ~= e.id then DZ.unwear(oid) end
        end
    end
    t.seq = t.seq + 1
    t.ord[e.id] = t.seq
    S.worn[e.id] = e
    addHistory({id = e.id, name = e.name, cat = e.cat, group = e.group, slot = e.slot})
    if e.kind == "Acc" then
        P.cfg(e.id)
        if not P.sel or not S.worn[P.sel] then P.sel = e.id end
    end
    if t.kind == "me" then applyAll(t) else t.dirty = true end
    DZ.Prev.dirty = true
    DZ.repaint()
    local note = ""
    if e.layered then note = " | layered: dipasang kaku" end
    if e.kind == "Body" then note = " | body part: overlay R15 & R6" end
    DZ.log((t.kind == "me" and "Dipakai: " or "Draft Friend: ") .. tostring(e.name) .. " (" .. e.kind .. ")" .. note)
end

function DZ.toggleTry(item)
    local id = item.id
    if S.worn[id] then
        DZ.unwear(id)
        DZ.repaint()
        DZ.log("Dilepas: " .. tostring(item.name))
        return
    end
    DZ.log("Memuat " .. tostring(item.name) .. "...")
    loadEntry(id, item.name, function(e)
        if not S.alive then return end
        if not e then
            DZ.log("Gagal memuat ID " .. id .. " (bukan item avatar / tidak bisa dimuat)")
            return
        end
        DZ.wear(e, item)
    end)
end

function DZ.setFlag(name, on)
    local t = DZ.cur
    S.flags[name] = on
    if t.kind == "me" then
        for _, c in ipairs(allChars(player)) do
            if name == "headless" then pcall(setHeadOn, c, not on)
            elseif name == "korblox" and not on then pcall(KB.removeR, c)
            elseif name == "korbloxL" and not on then pcall(KB.removeL, c) end
        end
        if on then pcall(applyAll, t) end
    else
        t.dirty = true
    end
    DZ.Prev.dirty = true
    DZ.repaint()
end

-- reset avatar sendiri (langsung ke dunia)
function DZ.resetMe()
    local t = DZ.me
    for id, e in pairs(t.worn) do
        worldRemove(t, id, e)
        t.worn[id] = nil
    end
    t.flags.headless, t.flags.korblox, t.flags.korbloxL = false, false, false
    worldFlagsOff(t)
    if DZ.cur == t then P.sel = nil end
    DZ.Prev.dirty = true
    DZ.repaint()
end

-- kosongkan draft target yang sedang diedit (Friend: dunia tidak berubah sampai Apply)
function DZ.clearDraft()
    local t = DZ.cur
    if t.kind == "me" then DZ.resetMe() return end
    for id in pairs(t.worn) do t.worn[id] = nil end
    for k in pairs(t.flags) do t.flags[k] = false end
    for id in pairs(t.posCfg) do t.posCfg[id] = nil end
    t.dirty = true
    P.sel = nil
    DZ.Prev.dirty = true
    DZ.repaint()
end

-- ================= SLOT FRIEND =================
DZ.slots = {}
function DZ.addSlot() DZ.slots[#DZ.slots + 1] = {t = nil} end
for _ = 1, 4 do DZ.addSlot() end

function DZ.setTarget(t)
    t = t or DZ.me
    DZ.cur = t
    S.worn, S.flags, S.posCfg, S.orig = t.worn, t.flags, t.posCfg, t.orig
    P.sel = nil
    for _, e in ipairs(DZ.wornList()) do
        if e.kind == "Acc" then P.sel = e.id break end
    end
    DZ.Prev.dirty = true
    if DZ.onTarget then pcall(DZ.onTarget) end
    DZ.repaint()
end

function DZ.pickFriend(i, plr)
    local s = DZ.slots[i]
    if not s or not plr or plr == player then return false, "Pemain tidak valid" end
    for j, o in ipairs(DZ.slots) do
        if j ~= i and o.t and o.t.userId == plr.UserId then return false, "Sudah ada di slot " .. j end
    end
    if s.t and s.t.userId == plr.UserId then return true end
    if s.t then DZ.clearSlot(i) end
    s.t = newTarget("friend", plr)
    return true
end

-- hapus semua perubahan teman (draft + yang sudah di-Apply)
function DZ.friendReset(t)
    for id, e in pairs(t.live) do
        worldRemove(t, id, e)
        t.live[id] = nil
    end
    worldFlagsOff(t)
    for k in pairs(t.liveFlags) do t.liveFlags[k] = false end
    for id in pairs(t.liveCfg) do t.liveCfg[id] = nil end
    for id in pairs(t.worn) do t.worn[id] = nil end
    for k in pairs(t.flags) do t.flags[k] = false end
    for id in pairs(t.posCfg) do t.posCfg[id] = nil end
    t.dirty = false
    if DZ.cur == t then P.sel = nil end
    DZ.Prev.dirty = true
    DZ.repaint()
end

function DZ.clearSlot(i)
    local s = DZ.slots[i]
    if not s or not s.t then return end
    local t = s.t
    DZ.friendReset(t)
    if DZ.cur == t then DZ.setTarget(DZ.me) end
    s.t = nil
    DZ.repaint()
end

-- APPLY: salin draft ke live lalu pasang ke karakter teman
function DZ.friendApply(t)
    if not plrOf(t) then return false, "Teman tidak ada di server" end
    for id, e in pairs(t.live) do
        worldRemove(t, id, e)
        t.live[id] = nil
    end
    worldFlagsOff(t)
    for id in pairs(t.liveCfg) do t.liveCfg[id] = nil end
    for id, e in pairs(t.worn) do
        t.live[id] = e
        if e.kind == "Acc" then
            local c, d = P.cfgIn(t.posCfg, id), P.cfgIn(t.liveCfg, id)
            for _, k in ipairs(P.KEYS) do d[k] = c[k] end
        end
    end
    for k, v in pairs(t.flags) do t.liveFlags[k] = v end
    t.dirty = false
    applyAll(t)
    DZ.repaint()
    return true
end

function DZ.friendStatus(t)
    if not t then return "Empty" end
    if not plrOf(t) then return "Offline" end
    if t.dirty then return "Belum di-Apply" end
    if next(t.live) ~= nil or t.liveFlags.headless or t.liveFlags.korblox or t.liveFlags.korbloxL then return "Applied" end
    return "Selected"
end

-- re-apply untuk semua target: kalau Evade ganti model, hasilnya ikut pindah
do
    local acc = 0
    local function run(t)
        local lf = t.liveFlags
        if next(t.live) ~= nil or lf.headless or lf.korblox or lf.korbloxL then pcall(applyAll, t) end
    end
    connect(RunService.Heartbeat, function(dt)
        if not S.settings.reapply then return end
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        run(DZ.me)
        for _, s in ipairs(DZ.slots) do
            if s.t then run(s.t) end
        end
    end)
end

function DZ.cleanupAll()
    pcall(DZ.resetMe)
    for _, s in ipairs(DZ.slots) do
        if s.t then pcall(DZ.friendReset, s.t) end
    end
end

-- ================= PRESET (target yang sedang diedit) =================
function DZ.presetSave(name)
    local items = {}
    for _, e in ipairs(DZ.wornList()) do
        items[#items + 1] = {
            id = e.id, name = e.name, cat = e.cat, group = e.group, slot = e.slot,
            kind = e.kind, cfg = (e.kind == "Acc") and P.copy(e.id) or nil,
        }
    end
    DZ.presets[name] = {
        flags = {headless = S.flags.headless, korblox = S.flags.korblox, korbloxL = S.flags.korbloxL},
        items = items,
    }
    DZ.Storage.save("presets", DZ.presets)
end

function DZ.presetDelete(name)
    DZ.presets[name] = nil
    DZ.Storage.save("presets", DZ.presets)
end

function DZ.presetLoad(name)
    local p = DZ.presets[name]
    if type(p) ~= "table" then return false end
    DZ.clearDraft()
    local f = p.flags or {}
    for _, k in ipairs({"headless", "korblox", "korbloxL"}) do
        if f[k] then DZ.setFlag(k, true) end
    end
    local items = p.items or {}
    local target = DZ.cur
    for i = #items, 1, -1 do
        local it = items[i]
        if type(it) == "table" and it.id then
            if type(it.cfg) == "table" then
                local c = P.cfgIn(target.posCfg, it.id)
                for _, k in ipairs(P.KEYS) do
                    if type(it.cfg[k]) == "number" then c[k] = it.cfg[k] end
                end
            end
            loadEntry(it.id, it.name, function(e)
                if e and S.alive and DZ.cur == target then DZ.wear(e, it, true) end
            end)
        end
    end
    return true
end

-- diekspor untuk panel preview (menampilkan DRAFT friend pada salinan karakter)
DZ.putCloth, DZ.putFace, DZ.setHeadOn, DZ.KB = putCloth, putFace, setHeadOn, KB
-- ================= FAVORITES =================
do
    local F = DZ.Fav
    F.list = DZ.Storage.load("favorites", {})
    if type(F.list) ~= "table" then F.list = {} end
    F.set = {}
    F.onChange = {}
    for _, it in ipairs(F.list) do
        if type(it) == "table" and it.id then F.set[it.id] = true end
    end

    function F.has(id) return F.set[id] == true end

    function F.save() DZ.Storage.save("favorites", F.list) end

    local function fire()
        for _, fn in ipairs(F.onChange) do pcall(fn) end
    end

    function F.toggle(item)
        if F.set[item.id] then
            F.set[item.id] = nil
            for i, it in ipairs(F.list) do
                if it.id == item.id then table.remove(F.list, i) break end
            end
        else
            F.set[item.id] = true
            table.insert(F.list, 1, {id = item.id, name = item.name, cat = item.cat, group = item.group, slot = item.slot})
        end
        F.save()
        fire()
        return F.set[item.id] == true
    end

    function F.clear()
        F.list = {}
        F.set = {}
        F.save()
        fire()
    end
end

-- ================= STATUS LIMITED (validasi dari MarketplaceService) =================
do
    local Stt = DZ.Status
    Stt.cache, Stt.queue, Stt.waiting, Stt.running = {}, {}, {}, false

    local function worker()
        while S.alive and #Stt.queue > 0 do
            local job = table.remove(Stt.queue, 1)
            local ok, info = pcall(function()
                return MarketplaceService:GetProductInfo(job.id, Enum.InfoType.Asset)
            end)
            local res = {status = "Unknown"}
            if ok and type(info) == "table" then
                res.name = info.Name
                res.price = info.PriceInRobux
                res.forSale = info.IsForSale
                res.remaining = info.Remaining
                res.sales = info.Sales
                res.desc = info.Description
                if type(info.Creator) == "table" then res.creator = info.Creator.Name end
                if info.IsLimitedUnique == true then
                    res.status = "Limited U"
                elseif info.IsLimited == true then
                    res.status = "Limited"
                elseif info.CollectiblesItemDetails ~= nil or job.hint then
                    res.status = "Collectible" -- hasil filter koleksi Roblox
                else
                    res.status = "Regular"
                end
            end
            Stt.cache[job.id] = res
            local cbs = Stt.waiting[job.id] or {}
            Stt.waiting[job.id] = nil
            for _, cb in ipairs(cbs) do pcall(cb, res) end
            task.wait(0.15)
        end
        Stt.running = false
    end

    function Stt.request(id, hint, cb)
        local c = Stt.cache[id]
        if c then cb(c) return end
        local w = Stt.waiting[id]
        if not w then
            w = {}
            Stt.waiting[id] = w
            table.insert(Stt.queue, {id = id, hint = hint})
        end
        table.insert(w, cb)
        if not Stt.running then
            Stt.running = true
            task.spawn(worker)
        end
    end
end

-- ================= MESIN KATALOG (AvatarEditorService) =================
do
    local Cat = DZ.Cat
    Cat.cache, Cat.count = {}, 0

    function Cat.ats(names)
        local out = {}
        for _, n in ipairs(names) do
            local ok, v = pcall(function() return Enum.AvatarAssetType[n] end)
            if ok and v then out[#out + 1] = v end
        end
        return out
    end

    local SORTS = {
        {"Relevansi", "Relevance"}, {"Favorit", "MostFavorited"}, {"Terlaris", "Bestselling"},
        {"Terbaru", "RecentlyCreated"}, {"Termahal", "PriceHighToLow"}, {"Termurah", "PriceLowToHigh"},
    }
    Cat.sorts = {}
    for _, s in ipairs(SORTS) do
        local ok, v = pcall(function() return Enum.CatalogSortType[s[2]] end)
        if ok and v then Cat.sorts[#Cat.sorts + 1] = {name = s[1], enum = v} end
    end
    if #Cat.sorts == 0 then Cat.sorts[1] = {name = "Relevansi"} end

    local function normalize(it, spec)
        if type(it) ~= "table" or not it.Id then return nil end
        if tostring(it.ItemType):find("Bundle") then return nil end -- bundle tidak bisa dicoba sebagai satu asset
        local cat = spec.cat
        if not cat and it.AssetType then cat = tostring(it.AssetType):match("[^%.]+$") end
        return {
            id = it.Id, name = it.Name or ("ID " .. tostring(it.Id)), cat = cat or "Item",
            group = spec.group, slot = spec.slot,
        }
    end

    function Cat.session(key, spec)
        local s = Cat.cache[key]
        if not s then
            if Cat.count > 25 then Cat.cache, Cat.count = {}, 0 end
            s = {spec = spec, list = {}, n = 0, finished = false, busy = false}
            Cat.cache[key] = s
            Cat.count = Cat.count + 1
        end
        return s
    end

    function Cat.clear() Cat.cache, Cat.count = {}, 0 end

    -- ambil halaman berikutnya; cb(ok, itemsAtauPesanError)
    function Cat.fetch(s, cb)
        if s.busy then return end
        if s.finished then cb(false, "Sudah halaman terakhir") return end
        s.busy = true
        task.spawn(function()
            local ok, res = pcall(function()
                local pages = s.pages
                if not pages then
                    local p = CatalogSearchParams.new()
                    p.SearchKeyword = s.spec.kw or ""
                    p.Limit = 30
                    if s.spec.types and #s.spec.types > 0 then p.AssetTypes = s.spec.types end
                    if s.spec.sort then pcall(function() p.SortType = s.spec.sort end) end
                    if s.spec.collect then
                        pcall(function() p.SalesTypeFilter = Enum.SalesTypeFilter.Collectibles end)
                        pcall(function() p.IncludeOffSale = true end)
                    end
                    pages = AES:SearchCatalogAsync(p)
                else
                    pages:AdvanceToNextPageAsync()
                end
                return {pages = pages, cur = pages:GetCurrentPage(), fin = pages.IsFinished}
            end)
            s.busy = false
            if not S.alive then return end
            if not ok then
                cb(false, tostring(res):sub(1, 120))
                return
            end
            s.pages = res.pages
            s.finished = res.fin == true
            local items = {}
            for _, it in ipairs(res.cur) do
                local n = normalize(it, s.spec)
                if n then items[#items + 1] = n end
            end
            s.n = s.n + 1
            s.list[s.n] = items
            cb(true, items)
        end)
    end
end

-- =====================================================================
-- ======================= UI (UIController) ===========================
-- Mode tertanam: dipasang ke tab "Catalog" di script utama lewat _G.DZ_CATALOG_HOST
-- Mode mandiri : membuat jendela sendiri bila host tidak ada
-- =====================================================================
local UI = DZ.UI
UI.reg = setmetatable({}, {__mode = "k"})
UI.pages = {}
UI.order = 0
UI.current = nil
UI.step = 0.05

local HOST = _G.DZ_CATALOG_HOST
if type(HOST) ~= "table" or typeof(HOST.parent) ~= "Instance" then HOST = nil end
local TH = (HOST and type(HOST.theme) == "table") and HOST.theme or {}
UI.embedded = HOST ~= nil

local function hex(s) return Color3.fromHex(s) end
local C = {
    bg = TH.BG or hex("0A0A0A"), black = TH.BLACK or hex("000000"), glass = TH.GLASS or hex("101010"),
    card = TH.CARD or hex("0D0D0D"), line = TH.LINE or hex("242424"), gray = TH.GRAY or hex("929292"),
    white = TH.WHITE or hex("F5F5F5"), red = TH.RED or hex("FF4D4D"), deep = TH.DEEP or hex("8B1010"),
    green = TH.GREEN or hex("22C55E"), gold = Color3.fromRGB(255, 200, 60), accent = TH.accent or hex("FF2020"),
}
UI.C = C
local FONT, FONT_B = Enum.Font.GothamMedium, Enum.Font.GothamBold
local GOLD_TXT = Color3.fromRGB(24, 16, 0)

-- objek beraksen: ikut berubah kalau tema aksen di script utama diganti
local accObjs = setmetatable({}, {__mode = "k"})
local accHooks = {}
local function accPaint(inst, prop)
    inst[prop] = C.accent
    accObjs[inst] = prop
end
if HOST and type(HOST.onAccent) == "function" then
    pcall(HOST.onAccent, function(col)
        C.accent = col
        for inst, prop in pairs(accObjs) do pcall(function() inst[prop] = col end) end
        for _, f in ipairs(accHooks) do pcall(f) end
    end)
end

local function mk(class, props, parent)
    local i = Instance.new(class)
    for k, v in pairs(props) do i[k] = v end
    if parent then i.Parent = parent end
    return i
end

local function corner(inst, r)
    mk("UICorner", {CornerRadius = UDim.new(0, r or 8)}, inst)
    return inst
end

local function lstroke(inst, color, th, tr)
    return mk("UIStroke", {
        Color = color or C.line, Thickness = th or 1, Transparency = tr or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, inst)
end

local function tween(inst, t, props, style)
    TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function txt(parent, text, size, color, props)
    local l = mk("TextLabel", {
        Text = text, TextSize = size or 11, TextColor3 = color or C.white, Font = FONT,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0,
    }, parent)
    if props then for k, v in pairs(props) do l[k] = v end end
    return l
end

local function para(parent, text, size, color)
    return txt(parent, text, size or 10, color or C.gray, {
        Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
    })
end

-- tombol bergaya script utama: kaca gelap + garis tipis; "accent" / "danger" / "gold" untuk aksi utama
local function btn(parent, text, kind, pos, size, ts)
    local b = mk("TextButton", {
        Text = text, Position = pos, Size = size, BackgroundColor3 = C.glass, TextColor3 = C.white,
        Font = FONT_B, TextSize = ts or 11, AutoButtonColor = false, BorderSizePixel = 0,
    }, parent)
    corner(b, 7)
    local st = lstroke(b, C.white, 1, 0.88)
    local sc = mk("UIScale", {}, b)
    if kind == "accent" then
        accPaint(b, "BackgroundColor3")
        st.Transparency = 1
    elseif kind == "danger" then
        b.BackgroundColor3 = C.deep
        st.Color, st.Transparency = C.red, 0.55
    elseif kind == "gold" then
        b.BackgroundColor3 = C.gold
        b.TextColor3 = GOLD_TXT
        st.Transparency = 1
    end
    b.MouseEnter:Connect(function() tween(b, 0.12, {BackgroundTransparency = 0.2}) end)
    b.MouseLeave:Connect(function()
        tween(b, 0.12, {BackgroundTransparency = 0})
        tween(sc, 0.1, {Scale = 1})
    end)
    b.MouseButton1Down:Connect(function() tween(sc, 0.07, {Scale = 0.94}) end)
    b.MouseButton1Up:Connect(function() tween(sc, 0.14, {Scale = 1}, Enum.EasingStyle.Back) end)
    return b, st
end

local function scroller(parent, pos, size)
    return mk("ScrollingFrame", {
        Position = pos, Size = size, BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.line, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
    }, parent)
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function vscale()
    local s = 1
    if HOST and type(HOST.getScale) == "function" then
        local ok, v = pcall(HOST.getScale)
        if ok and type(v) == "number" and v > 0 then s = v end
    end
    if UI.ownScale then s = s * UI.ownScale.Scale end
    return s
end

-- ================= ROOT: tertanam di tab, atau jendela mandiri =================
local gui, root
if HOST then
    gui = HOST.parent
    root = mk("Frame", {Name = "DZCatalogRoot", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1}, HOST.parent)
else
    gui = mk("ScreenGui", {
        Name = "DZ_AvatarCatalog", ResetOnSpawn = false, DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    local ok = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not ok or not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end
    local WIN_W, WIN_H = 540, 410
    local main = mk("Frame", {
        Name = "Main", Size = UDim2.new(0, WIN_W, 0, WIN_H), Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
        BackgroundColor3 = C.bg, BorderSizePixel = 0, ClipsDescendants = true,
    }, gui)
    corner(main, 14)
    lstroke(main, C.line, 1, 0)
    local vs = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(900, 600)
    UI.ownScale = mk("UIScale", {Scale = math.clamp(math.min((vs.X - 16) / WIN_W, (vs.Y - 16) / WIN_H), 0.5, 1)}, main)
    local header = mk("Frame", {Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = C.glass, BorderSizePixel = 0}, main)
    txt(header, "DZ AVATAR CATALOG", 12, C.white, {Font = FONT_B, Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -80, 1, 0)})
    local minB = btn(header, "-", nil, UDim2.new(1, -54, 0.5, -11), UDim2.new(0, 22, 0, 22), 13)
    local clsB = btn(header, "X", "danger", UDim2.new(1, -28, 0.5, -11), UDim2.new(0, 22, 0, 22), 11)
    UI.minB, UI.clsB, UI.main, UI.WIN = minB, clsB, main, {WIN_W, WIN_H}
    local dragging, startPos, startUi = false, nil, nil
    connect(header.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startUi = true, i.Position, main.Position
            local c
            c = i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false c:Disconnect() end
            end)
        end
    end)
    connect(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startPos
            main.Position = UDim2.new(startUi.X.Scale, startUi.X.Offset + d.X, startUi.Y.Scale, startUi.Y.Offset + d.Y)
        end
    end)
    root = mk("Frame", {Position = UDim2.new(0, 10, 0, 36), Size = UDim2.new(1, -20, 1, -44), BackgroundTransparency = 1}, main)
    UI.body = root
end
UI.gui, UI.root = gui, root

-- ================= NAV (pill) =================
local NAV = {
    {"home", "Home"}, {"catalog", "Katalog"}, {"acc", "Aksesoris"}, {"clo", "Pakaian"}, {"body", "Body"},
    {"ltd", "Limited"}, {"fav", "Favorit"}, {"editor", "Editor"}, {"wardrobe", "Wardrobe"},
    {"friend", "Friend"}, {"settings", "Setelan"},
}
local nav = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
}, root)
mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), VerticalAlignment = Enum.VerticalAlignment.Center}, nav)
UI.nav = {}
for _, e in ipairs(NAV) do
    local b = btn(nav, e[2], nil, nil, UDim2.new(0, math.max(54, #e[2] * 7 + 20), 0, 24), 10)
    UI.nav[e[1]] = b
    b.MouseButton1Click:Connect(function() UI.show(e[1]) end)
end

-- ================= BANNER TARGET (muncul saat mengedit Friend) =================
local banner = mk("Frame", {Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.glass, Visible = false, BorderSizePixel = 0}, root)
corner(banner, 8)
local bannerStroke = lstroke(banner, C.accent, 1, 0.4)
accObjs[bannerStroke] = "Color"
local bannerTxt = txt(banner, "", 10, C.white, {Font = FONT_B, Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -190, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd})
local bApply = btn(banner, "APPLY", "accent", UDim2.new(1, -184, 0.5, -10), UDim2.new(0, 58, 0, 20), 10)
local bReset = btn(banner, "RESET", "danger", UDim2.new(1, -122, 0.5, -10), UDim2.new(0, 56, 0, 20), 10)
local bMe = btn(banner, "Saya", nil, UDim2.new(1, -62, 0.5, -10), UDim2.new(0, 56, 0, 20), 10)

bApply.MouseButton1Click:Connect(function()
    local t = DZ.cur
    if t.kind == "me" then return end
    local ok, err = DZ.friendApply(t)
    DZ.log(ok and ("Apply ke " .. tostring(t.display) .. " berhasil (visual lokal).") or ("Apply gagal: " .. tostring(err)))
    UI.bannerUpdate()
end)
bReset.MouseButton1Click:Connect(function()
    local t = DZ.cur
    if t.kind == "me" then return end
    UI.confirm("Hapus SEMUA perubahan untuk " .. tostring(t.display) .. "?", function()
        DZ.friendReset(t)
        DZ.log("Perubahan " .. tostring(t.display) .. " dihapus.")
        UI.bannerUpdate()
    end)
end)
bMe.MouseButton1Click:Connect(function() DZ.setTarget(DZ.me) end)

-- ================= CONTENT + STATUS BAR =================
local content = mk("Frame", {Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 1, -52), BackgroundTransparency = 1, ClipsDescendants = true}, root)
UI.content = content
local bar = mk("Frame", {Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1}, root)
local logLbl = txt(bar, "Siap.", 9, C.gray, {Size = UDim2.new(0.62, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd})
local rigLbl = txt(bar, "", 9, C.green, {Font = FONT_B, Position = UDim2.new(0.62, 0, 0, 0), Size = UDim2.new(0.38, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right})
DZ.log = function(t)
    logLbl.Text = tostring(t)
    if HOST and type(HOST.notify) == "function" and UI.toast then pcall(HOST.notify, tostring(t)) end
end

function UI.layout()
    local showB = DZ.cur.kind ~= "me"
    banner.Visible = showB
    local y = 32 + (showB and 32 or 0)
    content.Position = UDim2.new(0, 0, 0, y)
    content.Size = UDim2.new(1, 0, 1, -(y + 20))
end

function UI.bannerUpdate()
    local t = DZ.cur
    if t.kind == "me" then return end
    local s = DZ.friendStatus(t)
    bannerTxt.Text = "Mengedit " .. DZ.targetLabel(t) .. "  |  " .. s
    bApply.Visible = true
end

-- ================= REGISTRY TOMBOL (Coba / Hati / ring / titik) =================
function UI.paint(b, r)
    if r.kind == "try" then
        local on = S.worn[r.id] ~= nil
        b.Text = on and "Lepas" or (r.draft and "Coba" or "Coba")
        if on then
            b.BackgroundColor3 = C.deep
            accObjs[b] = nil
        else
            accPaint(b, "BackgroundColor3")
        end
    elseif r.kind == "heart" then
        b.TextColor3 = DZ.Fav.has(r.id) and C.red or C.gray
    elseif r.kind == "dot" then
        b.Visible = S.worn[r.id] ~= nil
    elseif r.kind == "ring" then
        local on = S.worn[r.id] ~= nil
        if on then accPaint(b, "Color") else accObjs[b] = nil b.Color = C.line end
        b.Transparency = on and 0.1 or 0
        b.Thickness = on and 1.5 or 1
    end
end

function UI.paintAll()
    for b, r in pairs(UI.reg) do
        if b:IsDescendantOf(root) then UI.paint(b, r) else UI.reg[b] = nil end
    end
end

table.insert(DZ.Fav.onChange, function() UI.paintAll() end)

DZ.sources = {
    history = function() return S.history end,
    worn = function() return DZ.wornItems() end,
    fav = function() return DZ.Fav.list end,
}

-- ================= KARTU ITEM =================
local STATUS_COL = {["Limited U"] = C.gold, Limited = C.gold, Collectible = Color3.fromRGB(255, 150, 60)}

function UI.card(parent, item, o)
    o = o or {}
    local id = item.id
    UI.order = UI.order + 1
    local card = mk("Frame", {BackgroundColor3 = C.card, LayoutOrder = UI.order, Name = "Card", BorderSizePixel = 0}, parent)
    corner(card, 10)
    local ring = lstroke(card, C.line, 1, 0)
    UI.reg[ring] = {kind = "ring", id = id}

    local thumb = mk("Frame", {Position = UDim2.new(0, 6, 0, 6), Size = UDim2.new(1, -12, 0, 68), BackgroundColor3 = C.black, BorderSizePixel = 0}, card)
    corner(thumb, 8)
    mk("ImageLabel", {
        Size = UDim2.new(1, -6, 1, -6), Position = UDim2.new(0, 3, 0, 3), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
        Image = "rbxthumb://type=Asset&id=" .. tostring(id) .. "&w=150&h=150",
    }, thumb)
    local dot = corner(mk("Frame", {Position = UDim2.new(0, 5, 0, 5), Size = UDim2.new(0, 8, 0, 8), BackgroundColor3 = C.green, BorderSizePixel = 0, Visible = false}, thumb), 4)
    UI.reg[dot] = {kind = "dot", id = id}

    local nm = txt(card, tostring(item.name or id), 10, C.white, {
        Font = FONT_B, Position = UDim2.new(0, 8, 0, 78), Size = UDim2.new(1, -16, 0, 24),
        TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Top,
    })
    txt(card, "#" .. tostring(id) .. " | " .. tostring(item.cat or "-"), 9, C.gray, {
        Position = UDim2.new(0, 8, 0, 103), Size = UDim2.new(1, -16, 0, 11), TextTruncate = Enum.TextTruncate.AtEnd,
    })

    if o.limited then
        local stl = txt(card, "Status: cek...", 9, C.gray, {Font = FONT_B, Position = UDim2.new(0, 8, 0, 114), Size = UDim2.new(1, -16, 0, 11)})
        DZ.Status.request(id, o.hint, function(res)
            if not card:IsDescendantOf(root) then return end
            stl.Text = "Status: " .. res.status
            stl.TextColor3 = STATUS_COL[res.status] or C.gray
            if o.want and res.status ~= "Unknown" and not o.want[res.status] then card.Visible = false end
        end)
    end
    if item.needName then
        DZ.Status.request(id, false, function(res)
            if res.name and card:IsDescendantOf(root) then
                nm.Text = res.name
                item.name = res.name
            end
        end)
    end

    local try = btn(card, "Coba", "accent", UDim2.new(0, 6, 1, -30), UDim2.new(1, -42, 0, 24), 10)
    local heart = btn(card, "\226\153\165", nil, UDim2.new(1, -32, 1, -30), UDim2.new(0, 26, 0, 24), 14)
    local info = btn(thumb, "i", nil, UDim2.new(1, -21, 0, 5), UDim2.new(0, 16, 0, 16), 9)
    info.BackgroundTransparency = 0.25
    UI.reg[try] = {kind = "try", id = id}
    UI.reg[heart] = {kind = "heart", id = id}
    UI.paint(try, UI.reg[try])
    UI.paint(heart, UI.reg[heart])
    UI.paint(ring, UI.reg[ring])
    UI.paint(dot, UI.reg[dot])

    try.MouseButton1Click:Connect(function() DZ.toggleTry(item) end)
    heart.MouseButton1Click:Connect(function()
        DZ.Fav.toggle(item)
        heart.TextSize = 8
        tween(heart, 0.3, {TextSize = 14}, Enum.EasingStyle.Back)
    end)
    info.MouseButton1Click:Connect(function() UI.detail(item, o) end)
    return card
end

-- grid responsif: jumlah kolom menyesuaikan lebar (dalam satuan virtual UI)
local function makeGrid(scroll)
    local lay = mk("UIGridLayout", {
        CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    }, scroll)
    local function relayout()
        local w = scroll.AbsoluteSize.X / vscale() - 10
        if w < 60 then w = 220 end
        local cols = math.max(2, math.floor((w + 8) / 120))
        lay.CellSize = UDim2.new(0, math.floor((w - (cols - 1) * 8) / cols), 0, 152)
    end
    scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
    relayout()
    return lay
end

-- ================= MODAL =================
local function overlay()
    return mk("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
        Active = true, ZIndex = 20, Visible = false, BorderSizePixel = 0,
    }, root)
end

local function modalBox(ov, w, h)
    local p = mk("Frame", {
        Size = UDim2.new(0, w, 0, h), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundColor3 = C.bg, ZIndex = 21, BorderSizePixel = 0,
    }, ov)
    corner(p, 12)
    local st = lstroke(p, C.accent, 1, 0.45)
    accObjs[st] = "Color"
    return p
end

local function openModal(ov)
    ov.Visible = true
    local box = ov:FindFirstChildWhichIsA("Frame")
    if box then
        box.Size = box.Size - UDim2.new(0, 0, 0, 0)
        local sc = box:FindFirstChild("PopScale") or mk("UIScale", {Name = "PopScale"}, box)
        sc.Scale = 0.92
        tween(sc, 0.18, {Scale = 1}, Enum.EasingStyle.Back)
    end
end

function UI.confirm(text, onYes)
    if not UI.confirmOv then
        local ov = overlay()
        local p = modalBox(ov, 250, 112)
        local l = txt(p, "", 11, C.white, {
            Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -24, 0, 58), ZIndex = 22,
            TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
        })
        local yes = btn(p, "Ya", "danger", UDim2.new(0, 12, 1, -38), UDim2.new(0.5, -16, 0, 28), 11)
        local no = btn(p, "Batal", nil, UDim2.new(0.5, 4, 1, -38), UDim2.new(0.5, -16, 0, 28), 11)
        yes.ZIndex, no.ZIndex = 22, 22
        UI.confirmOv = {ov = ov, label = l}
        no.MouseButton1Click:Connect(function() ov.Visible = false end)
        yes.MouseButton1Click:Connect(function()
            ov.Visible = false
            if UI.confirmYes then pcall(UI.confirmYes) end
        end)
    end
    UI.confirmOv.label.Text = text
    UI.confirmYes = onYes
    openModal(UI.confirmOv.ov)
end

function UI.detail(item, o)
    local D = UI.detailUI
    if not D then
        local ov = overlay()
        local pw, ph = 300, 300
        local p = modalBox(ov, pw, ph)
        D = {ov = ov}
        local ib = corner(mk("Frame", {Position = UDim2.new(0, 12, 0, 12), Size = UDim2.new(0, 92, 0, 92), BackgroundColor3 = C.black, ZIndex = 22, BorderSizePixel = 0}, p), 10)
        D.img = mk("ImageLabel", {Size = UDim2.new(1, -8, 1, -8), Position = UDim2.new(0, 4, 0, 4), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 23}, ib)
        local function lb(y, h, col, font, size)
            return txt(p, "", size or 10, col or C.white, {
                Font = font or FONT, Position = UDim2.new(0, 114, 0, y), Size = UDim2.new(1, -126, 0, h), ZIndex = 22,
                TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Top,
            })
        end
        D.name = lb(12, 34, C.white, FONT_B, 12)
        D.id = lb(48, 14, C.gray)
        D.cat = lb(64, 14, C.gray)
        D.status = lb(82, 14, C.gray, FONT_B)
        local function full(y)
            return txt(p, "", 10, C.white, {Position = UDim2.new(0, 12, 0, y), Size = UDim2.new(1, -24, 0, 14), ZIndex = 22})
        end
        D.price = full(112)
        D.stock = full(128)
        D.creator = full(144)
        D.desc = txt(p, "", 9, C.gray, {
            Position = UDim2.new(0, 12, 0, 164), Size = UDim2.new(1, -24, 1, -164 - 46), ZIndex = 22,
            TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Top,
        })
        D.try = btn(p, "Coba", "accent", UDim2.new(0, 12, 1, -38), UDim2.new(0.46, -14, 0, 28), 11)
        D.heart = btn(p, "\226\153\165", nil, UDim2.new(0.46, 0, 1, -38), UDim2.new(0.14, -4, 0, 28), 15)
        D.close = btn(p, "Tutup", nil, UDim2.new(0.6, 4, 1, -38), UDim2.new(0.4, -16, 0, 28), 11)
        D.try.ZIndex, D.heart.ZIndex, D.close.ZIndex = 22, 22, 22
        D.close.MouseButton1Click:Connect(function() ov.Visible = false end)
        D.try.MouseButton1Click:Connect(function() if D.item then DZ.toggleTry(D.item) end end)
        D.heart.MouseButton1Click:Connect(function() if D.item then DZ.Fav.toggle(D.item) end end)
        UI.detailUI = D
    end
    o = o or {}
    D.item = item
    D.img.Image = "rbxthumb://type=Asset&id=" .. tostring(item.id) .. "&w=150&h=150"
    D.name.Text = tostring(item.name or item.id)
    D.id.Text = "Asset ID: " .. tostring(item.id)
    D.cat.Text = "Kategori: " .. tostring(item.cat or "-")
    D.status.Text = "Status: cek..."
    D.status.TextColor3 = C.gray
    D.price.Text, D.stock.Text, D.creator.Text, D.desc.Text = "Harga: -", "Stok / terjual: -", "Pembuat: -", ""
    UI.reg[D.try] = {kind = "try", id = item.id}
    UI.reg[D.heart] = {kind = "heart", id = item.id}
    UI.paint(D.try, UI.reg[D.try])
    UI.paint(D.heart, UI.reg[D.heart])
    openModal(D.ov)
    DZ.Status.request(item.id, o.hint, function(res)
        if D.item ~= item or not D.ov.Visible then return end
        D.status.Text = "Status: " .. res.status
        D.status.TextColor3 = STATUS_COL[res.status] or C.gray
        if res.status == "Unknown" then
            D.desc.Text = "Info katalog tidak tersedia (API gagal / item tidak punya data)."
            return
        end
        D.price.Text = "Harga: " .. (res.price and ("R$ " .. tostring(res.price)) or "-") .. (res.forSale == false and " (tidak dijual)" or "")
        D.stock.Text = "Stok: " .. (res.remaining and tostring(res.remaining) or "-") .. " | Terjual: " .. (res.sales and tostring(res.sales) or "-")
        D.creator.Text = "Pembuat: " .. tostring(res.creator or "-")
        D.desc.Text = tostring(res.desc or ""):sub(1, 220)
    end)
end

-- pilih pemain di server untuk slot Friend
function UI.pickPlayer(slotIndex, onDone)
    local K = UI.pickerUI
    if not K then
        local ov = overlay()
        local p = modalBox(ov, 330, 300)
        txt(p, "PILIH TEMAN (di server ini)", 11, C.white, {Font = FONT_B, Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -28, 0, 16), ZIndex = 22})
        local list = scroller(p, UDim2.new(0, 10, 0, 32), UDim2.new(1, -20, 1, -78))
        list.ZIndex = 22
        mk("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, list)
        local close = btn(p, "Tutup", nil, UDim2.new(0, 10, 1, -38), UDim2.new(1, -20, 0, 28), 11)
        close.ZIndex = 22
        close.MouseButton1Click:Connect(function() ov.Visible = false end)
        txt(p, "Hanya pemain yang ada di server ini yang bisa dipilih.", 9, C.gray, {Position = UDim2.new(0, 14, 1, -58), Size = UDim2.new(1, -28, 0, 12), ZIndex = 22})
        K = {ov = ov, list = list}
        UI.pickerUI = K
    end
    for _, c in ipairs(K.list:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            n = n + 1
            local used
            for j, s in ipairs(DZ.slots) do
                if s.t and s.t.userId == p.UserId and j ~= slotIndex then used = j end
            end
            local row = mk("Frame", {Size = UDim2.new(1, -6, 0, 44), BackgroundColor3 = C.card, LayoutOrder = n, ZIndex = 22, BorderSizePixel = 0}, K.list)
            corner(row, 9)
            lstroke(row, C.line, 1, 0)
            local av = corner(mk("ImageLabel", {
                Position = UDim2.new(0, 6, 0, 5), Size = UDim2.new(0, 34, 0, 34), BackgroundColor3 = C.black, ZIndex = 23, BorderSizePixel = 0,
                Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(p.UserId) .. "&w=150&h=150",
            }, row), 17)
            txt(row, tostring(p.DisplayName), 11, C.white, {Font = FONT_B, Position = UDim2.new(0, 48, 0, 5), Size = UDim2.new(1, -130, 0, 16), ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd})
            local isFriend = false
            pcall(function() isFriend = player:IsFriendsWith(p.UserId) end)
            txt(row, "@" .. p.Name .. (isFriend and "  |  Friend Roblox" or ""), 9, isFriend and C.green or C.gray, {Position = UDim2.new(0, 48, 0, 23), Size = UDim2.new(1, -130, 0, 12), ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd})
            local pick = btn(row, used and ("Slot " .. used) or "Pilih", (not used) and "accent" or nil, UDim2.new(1, -66, 0.5, -12), UDim2.new(0, 58, 0, 24), 10)
            pick.ZIndex = 23
            pick.MouseButton1Click:Connect(function()
                if used then return end
                local ok, err = DZ.pickFriend(slotIndex, p)
                if ok then
                    K.ov.Visible = false
                    DZ.log("Slot " .. slotIndex .. ": " .. tostring(p.DisplayName))
                    if onDone then onDone() end
                else
                    DZ.log(tostring(err))
                end
            end)
        end
    end
    if n == 0 then
        txt(K.list, "Tidak ada pemain lain di server.", 10, C.gray, {Size = UDim2.new(1, 0, 0, 30), ZIndex = 22})
    end
    openModal(K.ov)
end

-- ================= HALAMAN GRID =================
local SORT_LOCAL = {"Terbaru", "A-Z", "Z-A", "ID"}

local function buildGrid(def)
    local page = mk("Frame", {Name = def.key, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false}, content)
    local P = {frame = page, accent = def.gold and C.gold or C.accent, tab = 1, sort = 1, pageNo = 0, token = 0}
    local gold = def.gold == true
    local function mainCol() return gold and C.gold or C.accent end

    local box = mk("TextBox", {
        Size = UDim2.new(1, -140, 0, 28), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = C.glass, BorderSizePixel = 0,
        PlaceholderText = "Cari nama / Asset ID...", PlaceholderColor3 = C.gray, Text = "", TextColor3 = C.white,
        Font = FONT, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
    }, page)
    corner(box, 8)
    lstroke(box, C.white, 1, 0.88)
    mk("UIPadding", {PaddingLeft = UDim.new(0, 10)}, box)
    local searchBtn = btn(page, "Cari", gold and "gold" or "accent", UDim2.new(1, -134, 0, 0), UDim2.new(0, 58, 0, 28), 11)
    local sortBtn = btn(page, "Terbaru", nil, UDim2.new(1, -70, 0, 0), UDim2.new(0, 70, 0, 28), 10)

    local tabsFrame = mk("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 33), BackgroundTransparency = 1, ScrollBarThickness = 0,
        BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
    }, page)
    mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5)}, tabsFrame)

    local results = mk("ScrollingFrame", {
        Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 1, -90), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.line, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
    }, page)
    makeGrid(results)

    local msg = mk("Frame", {Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 1, -90), BackgroundTransparency = 1, Visible = false}, page)
    local msgLbl = txt(msg, "", 11, C.gray, {
        Position = UDim2.new(0, 10, 0.5, -44), Size = UDim2.new(1, -20, 0, 54), TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Bottom,
    })
    local retryBtn = btn(msg, "Coba Lagi", gold and "gold" or "accent", UDim2.new(0.5, -48, 0.5, 16), UDim2.new(0, 96, 0, 28), 11)

    local bottom = mk("Frame", {Position = UDim2.new(0, 0, 1, -26), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1}, page)
    local prevB = btn(bottom, "<", nil, UDim2.new(0, 0, 0, 0), UDim2.new(0, 36, 1, 0), 13)
    local pageL = txt(bottom, "", 10, C.gray, {Font = FONT_B, Position = UDim2.new(0, 40, 0, 0), Size = UDim2.new(0, 56, 1, 0), TextXAlignment = Enum.TextXAlignment.Center})
    local nextB = btn(bottom, ">", nil, UDim2.new(0, 100, 0, 0), UDim2.new(0, 36, 1, 0), 13)
    local moreB = btn(bottom, "Muat Lagi", gold and "gold" or "accent", UDim2.new(1, -92, 0, 0), UDim2.new(0, 92, 1, 0), 10)
    local clearB
    if def.removeAll then
        clearB = btn(bottom, "Hapus Semua", "danger", UDim2.new(1, -108, 0, 0), UDim2.new(0, 108, 1, 0), 10)
        clearB.Visible = false
    end

    local customs = {}
    local function clearCards()
        for _, c in ipairs(results:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
    end

    local function showMsg(text, retry)
        msg.Visible = text ~= nil
        msgLbl.Text = text or ""
        retryBtn.Visible = retry == true
    end

    local function skeleton(n)
        for i = 1, n do
            local f = corner(mk("Frame", {BackgroundColor3 = C.card, Name = "Skel", LayoutOrder = i, BorderSizePixel = 0}, results), 10)
            TweenService:Create(f, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.7}):Play()
        end
    end

    local function addCard(it)
        local tab = def.tabs[P.tab]
        UI.card(results, it, {limited = def.limited, want = tab.want, hint = def.collect})
    end

    local function sortName()
        local tab = def.tabs[P.tab]
        if tab.src then return SORT_LOCAL[P.sort] or SORT_LOCAL[1] end
        return (DZ.Cat.sorts[P.sort] or DZ.Cat.sorts[1]).name
    end

    local function sortCount()
        local tab = def.tabs[P.tab]
        if tab.src then return #SORT_LOCAL end
        return #DZ.Cat.sorts
    end

    function P.updateBottom()
        local tab = def.tabs[P.tab]
        local api = (not tab.src) and (not tab.static) and (not tab.custom) and P.session ~= nil
        prevB.Visible, nextB.Visible, pageL.Visible, moreB.Visible = api, api, api, api
        if clearB then clearB.Visible = (tab.src == "fav") end
        if api then
            local s = P.session
            pageL.Text = "Hal " .. tostring(P.pageNo)
            prevB.TextTransparency = (P.pageNo > 1) and 0 or 0.6
            nextB.TextTransparency = (s.list[P.pageNo + 1] ~= nil or not s.finished) and 0 or 0.6
            moreB.TextTransparency = s.finished and 0.6 or 0
        end
    end

    local function showPageNo(s, n)
        P.pageNo = n
        clearCards()
        showMsg(nil)
        local list = s.list[n] or {}
        for _, it in ipairs(list) do addCard(it) end
        if #list == 0 then showMsg("Tidak ada hasil") end
        results.CanvasPosition = Vector2.new(0, 0)
        P.updateBottom()
    end

    local function renderLocal(tab)
        local kw = trim(box.Text):lower()
        local list = {}
        for _, it in ipairs(DZ.sources[tab.src]()) do
            local ok = (not tab.group) or it.group == tab.group
            if ok and kw ~= "" then
                ok = tostring(it.name):lower():find(kw, 1, true) ~= nil or tostring(it.id):find(kw, 1, true) ~= nil
            end
            if ok then list[#list + 1] = it end
        end
        local sn = SORT_LOCAL[P.sort]
        if sn == "A-Z" then
            table.sort(list, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
        elseif sn == "Z-A" then
            table.sort(list, function(a, b) return tostring(a.name):lower() > tostring(b.name):lower() end)
        elseif sn == "ID" then
            table.sort(list, function(a, b) return a.id < b.id end)
        end
        for _, it in ipairs(list) do addCard(it) end
        if #list == 0 then showMsg(tab.empty or def.empty or "Kosong") end
        P.updateBottom()
    end

    function P.search()
        P.token = P.token + 1
        local tok = P.token
        local tab = def.tabs[P.tab]
        local kw = trim(box.Text)
        clearCards()
        showMsg(nil)
        P.session = nil
        P.pageNo = 0
        -- tab kustom (mis. kontrol Body): tampilkan panel sendiri
        for _, cf in pairs(customs) do cf.frame.Visible = false end
        local isCustom = tab.custom ~= nil
        results.Visible = not isCustom
        box.Visible, searchBtn.Visible, sortBtn.Visible = not isCustom, not isCustom, not isCustom
        if isCustom then
            local cf = customs[P.tab]
            if cf then
                cf.frame.Visible = true
                pcall(cf.refresh)
            end
            P.updateBottom()
            return
        end
        if P.sort > sortCount() then P.sort = 1 end
        sortBtn.Text = sortName()
        if tab.src then
            renderLocal(tab)
            return
        end
        if tab.static and kw == "" then
            for _, f in ipairs(tab.static) do
                addCard({id = f[1], name = f[2], cat = tab.cat, group = def.group, slot = tab.slot})
            end
            P.updateBottom()
            return
        end
        if kw:match("^%d+$") then
            addCard({id = tonumber(kw), name = "ID " .. kw, cat = "Asset ID", group = def.group, slot = tab.slot, needName = true})
            P.updateBottom()
            return
        end
        if tab.types and #tab.types == 0 then
            showMsg("Kategori ini tidak didukung oleh API / executor kamu.")
            P.updateBottom()
            return
        end
        local q = kw
        if tab.kw then q = trim(kw .. " " .. tab.kw) end
        local sortObj = DZ.Cat.sorts[P.sort] or DZ.Cat.sorts[1]
        local spec = {
            kw = q, types = tab.types, sort = sortObj.enum, collect = def.collect,
            cat = tab.cat, group = def.group, slot = tab.slot,
        }
        local key = def.key .. "|" .. tostring(P.tab) .. "|" .. q .. "|" .. tostring(P.sort)
        local s = DZ.Cat.session(key, spec)
        P.session = s
        if s.n >= 1 then
            showPageNo(s, 1)
            return
        end
        skeleton(8)
        if s.busy then
            task.delay(0.4, function() if tok == P.token then P.search() end end)
            return
        end
        DZ.Cat.fetch(s, function(ok, res)
            if tok ~= P.token then return end
            clearCards()
            if not ok then
                showMsg("Gagal memuat katalog:\n" .. tostring(res), true)
                P.updateBottom()
                return
            end
            if #res == 0 then showMsg("Tidak ada hasil") end
            for _, it in ipairs(res) do addCard(it) end
            P.pageNo = 1
            P.updateBottom()
        end)
    end

    function P.isWornTab() return def.tabs[P.tab].src == "worn" end

    local tabBtns = {}
    local function paintTabs()
        for i, b in ipairs(tabBtns) do
            local on = i == P.tab
            if on then
                accObjs[b] = nil
                b.BackgroundColor3 = mainCol()
                b.TextColor3 = gold and GOLD_TXT or C.white
            else
                b.BackgroundColor3 = C.glass
                b.TextColor3 = C.gray
            end
        end
    end
    accHooks[#accHooks + 1] = paintTabs
    for i, t in ipairs(def.tabs) do
        local b = btn(tabsFrame, t.name, nil, nil, UDim2.new(0, math.max(54, #t.name * 7 + 20), 1, 0), 10)
        tabBtns[i] = b
        if t.custom then
            local cf = mk("Frame", {Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 1, -62), BackgroundTransparency = 1, Visible = false}, page)
            local refresh = t.custom(cf)
            customs[i] = {frame = cf, refresh = refresh or function() end}
        end
        b.MouseButton1Click:Connect(function()
            P.tab = i
            P.sort = 1
            paintTabs()
            P.search()
        end)
    end
    paintTabs()

    searchBtn.MouseButton1Click:Connect(function() P.search() end)
    connect(box.FocusLost, function(enter) if enter then P.search() end end)
    do
        local deb = 0
        connect(box:GetPropertyChangedSignal("Text"), function()
            deb = deb + 1
            local my = deb
            task.delay(0.5, function()
                if my == deb and S.alive and UI.current == def.key then P.search() end
            end)
        end)
    end
    sortBtn.MouseButton1Click:Connect(function()
        P.sort = P.sort % sortCount() + 1
        P.search()
    end)
    retryBtn.MouseButton1Click:Connect(function()
        if P.session and P.session.n == 0 then P.session.pages = nil end
        P.search()
    end)
    prevB.MouseButton1Click:Connect(function()
        if P.session and P.pageNo > 1 then showPageNo(P.session, P.pageNo - 1) end
    end)
    nextB.MouseButton1Click:Connect(function()
        local s = P.session
        if not s then return end
        if s.list[P.pageNo + 1] then
            showPageNo(s, P.pageNo + 1)
        elseif not s.finished and not s.busy then
            DZ.log("Memuat halaman berikutnya...")
            DZ.Cat.fetch(s, function(ok, res)
                if s ~= P.session then return end
                if ok then showPageNo(s, s.n) else DZ.log("Gagal: " .. tostring(res)) end
            end)
        end
    end)
    moreB.MouseButton1Click:Connect(function()
        local s = P.session
        if not s or s.finished or s.busy then return end
        DZ.log("Memuat lagi...")
        DZ.Cat.fetch(s, function(ok, res)
            if s ~= P.session then return end
            if ok then
                for _, it in ipairs(res) do addCard(it) end
                P.pageNo = s.n
                P.updateBottom()
            else
                DZ.log("Gagal: " .. tostring(res))
            end
        end)
    end)
    if clearB then
        clearB.MouseButton1Click:Connect(function()
            if #DZ.Fav.list == 0 then return end
            UI.confirm("Hapus SEMUA item dari Favorit?", function() DZ.Fav.clear() end)
        end)
    end

    P.onShow = function()
        if def.tabs[P.tab].src or def.tabs[P.tab].custom or not P.loaded then
            P.loaded = true
            P.search()
        end
    end
    P.refreshCustom = function()
        local cf = customs[P.tab]
        if cf and cf.frame.Visible then pcall(cf.refresh) end
    end
    UI.pages[def.key] = P
    return P
end

-- ================= DATA TAB =================
local ats = DZ.Cat.ats
local ACC_ALL = ats({"Hat", "HairAccessory", "FaceAccessory", "NeckAccessory", "ShoulderAccessory", "FrontAccessory", "BackAccessory", "WaistAccessory"})
local CLO_ALL = ats({"Shirt", "Pants", "TShirt", "ShirtAccessory", "PantsAccessory", "TShirtAccessory", "JacketAccessory", "SweaterAccessory", "ShortsAccessory", "DressSkirtAccessory", "LeftShoeAccessory", "RightShoeAccessory"})
local LIM_ALL = {}
for _, v in ipairs(ACC_ALL) do LIM_ALL[#LIM_ALL + 1] = v end
for _, v in ipairs(CLO_ALL) do LIM_ALL[#LIM_ALL + 1] = v end

local FACES = {
    {7699174, "Winning Smile"}, {86487700, "Man Face"}, {86487773, "Woman Face"},
    {20418658, "Check It"}, {7074754, "Silly Fun"}, {14407565, "Joyful"},
}
local LIM_ANY = {["Limited"] = true, ["Limited U"] = true, ["Collectible"] = true}

buildGrid({
    key = "catalog", group = "GEN",
    tabs = {
        {name = "Semua", cat = nil},
        {name = "Aksesoris", types = ACC_ALL, cat = "Aksesoris"},
        {name = "Pakaian", types = CLO_ALL, cat = "Pakaian"},
        {name = "Wajah", types = ats({"Face"}), cat = "Face", slot = "Face", static = FACES},
        {name = "Riwayat", src = "history", empty = "Belum ada item yang pernah dicoba."},
        {name = "Dipakai", src = "worn", empty = "Belum ada item yang dipakai."},
    },
})

buildGrid({
    key = "acc", group = "ACC",
    tabs = {
        {name = "Semua", types = ACC_ALL, cat = "Aksesoris"},
        {name = "Hair", types = ats({"HairAccessory"}), cat = "Hair", slot = "Hair"},
        {name = "Hat / Topi", types = ats({"Hat"}), cat = "Hat"},
        {name = "Face", types = ats({"FaceAccessory"}), cat = "Face Acc", slot = "Face"},
        {name = "Neck", types = ats({"NeckAccessory"}), cat = "Neck", slot = "Neck"},
        {name = "Shoulder", types = ats({"ShoulderAccessory"}), cat = "Shoulder", slot = "Shoulder"},
        {name = "Front", types = ats({"FrontAccessory"}), cat = "Front", slot = "Front"},
        {name = "Back", types = ats({"BackAccessory"}), cat = "Back", slot = "Back"},
        {name = "Waist", types = ats({"WaistAccessory"}), cat = "Waist", slot = "Waist"},
        -- Ear / Eye / Head / Other tidak punya AssetType resmi: difilter dengan kata kunci
        {name = "Ear", types = ACC_ALL, kw = "ear", cat = "Ear"},
        {name = "Eye", types = ACC_ALL, kw = "eye", cat = "Eye"},
        {name = "Head", types = ats({"Hat", "HairAccessory", "FaceAccessory"}), kw = "head", cat = "Head"},
        {name = "Other", types = ACC_ALL, cat = "Other"},
    },
})

buildGrid({
    key = "clo", group = "CLO",
    tabs = {
        {name = "Semua", types = CLO_ALL, cat = nil},
        {name = "Kemeja", types = ats({"Shirt"}), cat = "Classic Shirt"},
        {name = "Celana", types = ats({"Pants"}), cat = "Classic Pants"},
        {name = "T-Shirt", types = ats({"TShirt"}), cat = "Classic T-Shirt"},
        {name = "Layered", types = ats({"ShirtAccessory", "PantsAccessory", "TShirtAccessory"}), cat = "Layered"},
        {name = "Jacket", types = ats({"JacketAccessory"}), cat = "Jacket"},
        {name = "Sweater", types = ats({"SweaterAccessory"}), cat = "Sweater"},
        {name = "Dress", types = ats({"DressSkirtAccessory"}), cat = "Dress"},
        {name = "Sepatu", types = ats({"LeftShoeAccessory", "RightShoeAccessory"}), cat = "Shoes"},
        {name = "Lainnya", types = ats({"ShortsAccessory"}), cat = "Other Clothing"},
    },
})

-- Body: tab kontrol (Headless / Korblox / reset) + katalog body part (R15)
buildGrid({
    key = "body", group = "BODY",
    tabs = {
        {name = "Kontrol", custom = function(cf)
            local sc = scroller(cf, UDim2.new(), UDim2.new(1, 0, 1, 0))
            mk("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, sc)
            local o = 0
            local paints = {}
            local note = para(sc, "", 10, C.gold)
            note.LayoutOrder = 1
            o = 1
            local function tg(text, key)
                o = o + 1
                local b = btn(sc, text, nil, nil, UDim2.new(1, -6, 0, 34), 11)
                b.LayoutOrder = o
                paints[#paints + 1] = function()
                    local on = S.flags[key]
                    if on then accPaint(b, "BackgroundColor3") else accObjs[b] = nil b.BackgroundColor3 = C.glass end
                    b.Text = text .. (on and "   [ON]" or "   [OFF]")
                end
                b.MouseButton1Click:Connect(function() DZ.setFlag(key, not S.flags[key]) end)
                return b
            end
            local items = {}
            items[#items + 1] = tg("Headless", "headless")
            items[#items + 1] = tg("Korblox Right", "korblox")
            items[#items + 1] = tg("Korblox Left", "korbloxL")
            local function act(text, fn, kind)
                o = o + 1
                local b = btn(sc, text, kind or "danger", nil, UDim2.new(1, -6, 0, 30), 11)
                b.LayoutOrder = o
                b.MouseButton1Click:Connect(fn)
                items[#items + 1] = b
            end
            act("Reset Head", function() DZ.setFlag("headless", false) DZ.log("Head direset.") end)
            act("Reset Body", function()
                DZ.setFlag("korblox", false)
                DZ.setFlag("korbloxL", false)
                for id, e in pairs(S.worn) do
                    if e.kind == "Body" then DZ.unwear(id) end
                end
                DZ.repaint()
                DZ.log("Body direset.")
            end)
            act("Reset Avatar (semua)", function()
                if DZ.cur.kind == "me" then DZ.resetMe() else DZ.clearDraft() end
                DZ.log("Avatar direset.")
            end)
            o = o + 1
            local n = para(sc, "Body part (kepala, badan, lengan, kaki) jalan di R15 dan R6 (Evade & map lain). Asset R6 klasik (CharacterMesh) hanya bisa di rig R6. Headless & Korblox memakai logic DZ untuk rig Evade.", 9)
            n.LayoutOrder = o
            UI.bodyPaint = function()
                local lock = UI.embedded and DZ.cur.kind == "me"
                note.Text = lock and "Untuk avatarmu sendiri, Headless & Korblox ada di tab Karakter (script utama). Pilih slot Friend untuk memakai kontrol ini pada teman." or ""
                note.Visible = lock
                for _, it in ipairs(items) do it.Visible = not lock end
                for _, f in ipairs(paints) do f() end
            end
            UI.bodyPaint()
            return UI.bodyPaint
        end},
        {name = "Head", types = ats({"Head"}), cat = "Head"},
        {name = "Torso", types = ats({"Torso"}), cat = "Torso"},
        {name = "Left Arm", types = ats({"LeftArm"}), cat = "Left Arm"},
        {name = "Right Arm", types = ats({"RightArm"}), cat = "Right Arm"},
        {name = "Left Leg", types = ats({"LeftLeg"}), cat = "Left Leg"},
        {name = "Right Leg", types = ats({"RightLeg"}), cat = "Right Leg"},
        {name = "Face", types = ats({"Face"}), cat = "Face", slot = "Face", static = FACES},
    },
})
if not UI.bodyPaint then UI.bodyPaint = function() end end

buildGrid({
    key = "ltd", group = "LTD", gold = true, limited = true, collect = true,
    tabs = {
        {name = "Limited", types = LIM_ALL, cat = nil, want = {["Limited"] = true, ["Limited U"] = true}},
        {name = "Limited U", types = LIM_ALL, cat = nil, want = {["Limited U"] = true}},
        {name = "Collectible", types = LIM_ALL, cat = nil, want = {["Collectible"] = true}},
        {name = "L. Aksesoris", types = ACC_ALL, cat = "Aksesoris", want = LIM_ANY},
        {name = "L. Hair", types = ats({"HairAccessory"}), cat = "Hair", slot = "Hair", want = LIM_ANY},
        {name = "L. Hat", types = ats({"Hat"}), cat = "Hat", want = LIM_ANY},
        {name = "L. Pakaian", types = CLO_ALL, cat = nil, want = LIM_ANY},
    },
})

do
    local favPage = buildGrid({
        key = "fav", group = "GEN", removeAll = true,
        empty = "Belum ada favorit.\nTekan ikon hati pada item untuk menambahkan.",
        tabs = {
            {name = "Semua", src = "fav"},
            {name = "Accessories", src = "fav", group = "ACC"},
            {name = "Clothing", src = "fav", group = "CLO"},
            {name = "Limited", src = "fav", group = "LTD"},
        },
    })
    table.insert(DZ.Fav.onChange, function()
        if UI.current == "fav" then favPage.search() end
    end)
end

-- ================= PREVIEW 3D (ViewportFrame + WorldModel) =================
do
    local Pv = DZ.Prev
    Pv.yaw, Pv.pitch, Pv.zoom = 0, 0.12, 1
    Pv.dirty, Pv.visible, Pv.spin = true, false, false
    Pv.target, Pv.base = Vector3.new(0, 0, 0), 9

    function Pv.updateCam()
        if not Pv.cam then return end
        local cp, sp = math.cos(Pv.pitch), math.sin(Pv.pitch)
        local off = Vector3.new(math.sin(Pv.yaw) * cp, sp, -math.cos(Pv.yaw) * cp) * (Pv.base * Pv.zoom)
        Pv.cam.CFrame = CFrame.lookAt(Pv.target + off, Pv.target)
    end

    function Pv.msg(t)
        if not Pv.msgLbl then return end
        Pv.msgLbl.Visible = t ~= nil
        Pv.msgLbl.Text = t or ""
    end

    function Pv.rebuild()
        local wm = Pv.wm
        if not wm then return end
        for _, c in ipairs(wm:GetChildren()) do c:Destroy() end
        local t = DZ.cur
        local src = DZ.curChar()
        if not src then Pv.msg(t.kind == "me" and "Karakter belum ketemu" or "Karakter teman tidak ada di server") return end
        local okc, clone = pcall(function()
            local old = src.Archivable
            src.Archivable = true
            local c = src:Clone()
            src.Archivable = old
            return c
        end)
        if not okc or not clone then Pv.msg("Preview tidak tersedia untuk rig ini") return end

        if t.kind ~= "me" then
            -- Friend: tampilkan DRAFT, bukan yang sudah dipasang di dunia
            for _, c in ipairs(clone:GetChildren()) do
                local n = c.Name
                if n:sub(1, #TAG) == TAG or n:sub(1, 11) == "FakeKorblox" then pcall(function() c:Destroy() end) end
            end
            for _, d in ipairs(clone:GetChildren()) do
                if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and (DZ.R15[d.Name] or d.Name:find("Arm") or d.Name:find("Leg") or d.Name == "Torso") then
                    d.Transparency = 0
                end
            end
            local orig = setmetatable({}, {__mode = "k"})
            for id, e in pairs(t.worn) do
                if e.kind == "Shirt" then pcall(DZ.putCloth, clone, "Shirt", "ShirtTemplate", e.tpl, orig)
                elseif e.kind == "Pants" then pcall(DZ.putCloth, clone, "Pants", "PantsTemplate", e.tpl, orig)
                elseif e.kind == "TShirt" then pcall(DZ.putCloth, clone, "ShirtGraphic", "Graphic", e.tpl, orig)
                elseif e.kind == "Face" then pcall(DZ.putFace, clone, e.tpl, orig)
                elseif e.kind == "Body" then pcall(DZ.applyBody, clone, id, e)
                elseif e.kind == "Acc" then pcall(DZ.attachAcc, clone, id, e, DZ.Pos.cfgIn(t.posCfg, id), true) end
            end
            if t.flags.headless then pcall(DZ.setHeadOn, clone, false) end
            if t.flags.korblox then pcall(DZ.KB.applyR, clone) end
            if t.flags.korbloxL then pcall(DZ.KB.applyL, clone) end
        end

        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("ForceField") then
                pcall(function() d:Destroy() end)
            end
        end
        local hum = clone:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum.EvaluateStateMachine = false end)
            pcall(function() hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
        end
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored = true end
        end
        local root_ = clone:FindFirstChild("HumanoidRootPart") or clone:FindFirstChild("Torso")
            or clone:FindFirstChild("UpperTorso") or clone:FindFirstChild("Head")
        if root_ and root_:IsA("BasePart") then clone.PrimaryPart = root_ end
        clone.Parent = wm
        local okp = pcall(function() clone:PivotTo(CFrame.new(0, 0, 0)) end)
        if not okp then Pv.msg("Preview tidak tersedia untuk rig ini") return end
        local okb, cf, size = pcall(function() return clone:GetBoundingBox() end)
        if okb and cf then
            Pv.target = cf.Position
            Pv.base = math.max(size.X, size.Y, size.Z) * 1.45 + 1
        end
        Pv.msg(nil)
        Pv.updateCam()
    end

    function Pv.setSpin(on)
        if on and not Pv.spinConn then
            Pv.spinConn = RunService.RenderStepped:Connect(function(dt)
                if not Pv.visible then return end
                Pv.yaw = Pv.yaw + dt * 0.9
                Pv.updateCam()
            end)
        elseif not on and Pv.spinConn then
            Pv.spinConn:Disconnect()
            Pv.spinConn = nil
        end
        Pv.spin = on
    end

    function Pv.view(name)
        if name == "front" then Pv.yaw, Pv.pitch = 0, 0.12
        elseif name == "back" then Pv.yaw, Pv.pitch = math.pi, 0.12
        elseif name == "side" then
            Pv.yaw = (math.abs(Pv.yaw - math.pi / 2) < 0.2) and -math.pi / 2 or math.pi / 2
            Pv.pitch = 0.12
        elseif name == "top" then Pv.yaw, Pv.pitch = 0, math.rad(85) end
        Pv.updateCam()
    end

    function Pv.zoomBy(f)
        Pv.zoom = math.clamp(Pv.zoom * f, 0.25, 3)
        Pv.updateCam()
    end
end

-- ================= EDITOR POSISI + PREVIEW =================
do
    local Pv = DZ.Prev
    local page = mk("Frame", {Name = "editor", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false}, content)
    local sc = scroller(page, UDim2.new(), UDim2.new(1, 0, 1, 0))
    mk("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, sc)
    local ord = 0
    local function nxt() ord = ord + 1 return ord end

    local holder = corner(mk("Frame", {Size = UDim2.new(1, -6, 0, 200), BackgroundColor3 = C.black, LayoutOrder = nxt(), BorderSizePixel = 0}, sc), 12)
    lstroke(holder, C.line, 1, 0)
    local vp = mk("ViewportFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.black, BorderSizePixel = 0,
        Ambient = Color3.fromRGB(150, 150, 165), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-0.4, -1, -0.5),
    }, holder)
    corner(vp, 12)
    Pv.cam = mk("Camera", {FieldOfView = 40}, vp)
    vp.CurrentCamera = Pv.cam
    Pv.wm = mk("WorldModel", {}, vp)
    Pv.msgLbl = txt(holder, "", 10, C.gray, {
        Position = UDim2.new(0, 10, 0.5, -20), Size = UDim2.new(1, -20, 0, 40), TextWrapped = true, Visible = false,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local tgtLbl = txt(holder, "", 10, C.white, {Font = FONT_B, Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -20, 0, 14), ZIndex = 3})
    Pv.tgtLbl = tgtLbl
    Pv.vp = vp

    do
        local dragging, last = false, nil
        vp.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging, last = true, i.Position
            end
        end)
        vp.InputChanged:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseWheel then Pv.zoomBy(i.Position.Z > 0 and 0.88 or 1.14) end
        end)
        connect(UIS.InputChanged, function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - last
                last = i.Position
                Pv.yaw = Pv.yaw - d.X * 0.012
                Pv.pitch = math.clamp(Pv.pitch + d.Y * 0.01, -0.6, math.rad(85))
                Pv.updateCam()
            end
        end)
        connect(UIS.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
    end

    local function gridRow(cols, h)
        local f = mk("Frame", {Size = UDim2.new(1, -6, 0, h), BackgroundTransparency = 1, LayoutOrder = nxt()}, sc)
        mk("UIGridLayout", {CellSize = UDim2.new(1 / cols, -5, 0, 26), CellPadding = UDim2.new(0, 5, 0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, f)
        return f
    end

    local views = gridRow(4, 26)
    for _, v in ipairs({{"Depan", "front"}, {"Belakang", "back"}, {"Samping", "side"}, {"Atas", "top"}}) do
        local b = btn(views, v[1], nil, nil, nil, 10)
        b.MouseButton1Click:Connect(function() Pv.view(v[2]) end)
    end

    local tools = gridRow(6, 26)
    local function tool(text, fn)
        local b = btn(tools, text, nil, nil, nil, 10)
        b.MouseButton1Click:Connect(fn)
        return b
    end
    tool("<", function() Pv.yaw = Pv.yaw + math.rad(30) Pv.updateCam() end)
    tool(">", function() Pv.yaw = Pv.yaw - math.rad(30) Pv.updateCam() end)
    tool("Zoom +", function() Pv.zoomBy(0.8) end)
    tool("Zoom -", function() Pv.zoomBy(1.25) end)
    local spinB = tool("Putar", function() end)
    spinB.MouseButton1Click:Connect(function()
        Pv.setSpin(not Pv.spin)
        if Pv.spin then accPaint(spinB, "BackgroundColor3") else accObjs[spinB] = nil spinB.BackgroundColor3 = C.glass end
    end)
    tool("Segar", function() Pv.dirty = true end)

    local selLbl = txt(sc, "Item dipilih:", 10, C.gray, {Font = FONT_B, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = nxt()})
    local chips = mk("ScrollingFrame", {
        Size = UDim2.new(1, -6, 0, 30), BackgroundTransparency = 1, ScrollBarThickness = 0, BorderSizePixel = 0, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, LayoutOrder = nxt(),
    }, sc)
    mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5)}, chips)

    local wrap = mk("Frame", {Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nxt()}, sc)
    local block = mk("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, wrap)
    mk("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, block)
    local lock = corner(mk("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.bg, BackgroundTransparency = 0.2, Active = true, ZIndex = 5, BorderSizePixel = 0}, wrap), 10)
    txt(lock, "Pasang item aksesori lalu pilih di atas.\nEditor posisi hanya aktif untuk item yang sedang dipakai.", 10, C.gray, {
        Position = UDim2.new(0, 10, 0, 24), Size = UDim2.new(1, -20, 0, 60), TextWrapped = true, ZIndex = 6, TextXAlignment = Enum.TextXAlignment.Center,
    })

    local bord = 0
    local function bn() bord = bord + 1 return bord end
    local updaters = {}
    local function hdr(text)
        txt(block, text, 10, C.gray, {Font = FONT_B, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = bn()})
    end

    local active
    connect(UIS.InputChanged, function(i)
        if active and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            active(i.Position.X)
        end
    end)
    connect(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then active = nil end
    end)

    local function sliderRow(key, text, fmt)
        local r = DZ.Pos.RANGE[key]
        local row = mk("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = bn()}, block)
        txt(row, text, 10, C.white, {Size = UDim2.new(0, 78, 1, 0)})
        local minus = btn(row, "-", nil, UDim2.new(0, 80, 0, 3), UDim2.new(0, 22, 0, 22), 13)
        local track = corner(mk("Frame", {BackgroundColor3 = C.line, Position = UDim2.new(0, 108, 0.5, -3), Size = UDim2.new(1, -108 - 82, 0, 6), BorderSizePixel = 0}, row), 3)
        local fill = corner(mk("Frame", {Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0}, track), 3)
        accPaint(fill, "BackgroundColor3")
        local knob = corner(mk("Frame", {BackgroundColor3 = C.white, Size = UDim2.new(0, 12, 0, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), BorderSizePixel = 0}, track), 6)
        local hit = mk("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0.5, -13)}, track)
        local plus = btn(row, "+", nil, UDim2.new(1, -78, 0, 3), UDim2.new(0, 22, 0, 22), 13)
        local box = mk("TextBox", {
            Position = UDim2.new(1, -52, 0, 3), Size = UDim2.new(0, 52, 0, 22), BackgroundColor3 = C.glass, Text = "", TextColor3 = C.white,
            Font = FONT, TextSize = 10, ClearTextOnFocus = false, BorderSizePixel = 0,
        }, row)
        corner(box, 6)
        lstroke(box, C.white, 1, 0.88)

        local function upd()
            local v = DZ.Pos.get(key)
            local tt = math.clamp((v - r[1]) / (r[2] - r[1]), 0, 1)
            fill.Size = UDim2.new(tt, 0, 1, 0)
            knob.Position = UDim2.new(tt, 0, 0.5, 0)
            if not box:IsFocused() then box.Text = string.format(fmt, v) end
        end
        updaters[#updaters + 1] = upd
        local function fromX(x)
            local w = track.AbsoluteSize.X
            if w <= 0 then return end
            local tt = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
            DZ.Pos.set(key, r[1] + (r[2] - r[1]) * tt)
        end
        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                active = fromX
                fromX(i.Position.X)
            end
        end)
        local stepOf = (key:sub(1, 1) == "r") and 5 or nil
        minus.MouseButton1Click:Connect(function() DZ.Pos.set(key, DZ.Pos.get(key) - (stepOf or UI.step)) end)
        plus.MouseButton1Click:Connect(function() DZ.Pos.set(key, DZ.Pos.get(key) + (stepOf or UI.step)) end)
        box.FocusLost:Connect(function()
            local n = tonumber(box.Text)
            if n then DZ.Pos.set(key, n) end
            upd()
        end)
    end

    hdr("POSITION  (X kanan/kiri karakter, Y atas/bawah, Z depan/belakang)")
    sliderRow("px", "X  Kanan/Kiri", "%.2f")
    sliderRow("py", "Y  Atas/Bawah", "%.2f")
    sliderRow("pz", "Z  Depan/Blkg", "%.2f")
    hdr("ROTATION")
    sliderRow("rx", "Rotate X", "%.0f")
    sliderRow("ry", "Rotate Y", "%.0f")
    sliderRow("rz", "Rotate Z", "%.0f")
    hdr("SCALE")
    sliderRow("su", "Ukuran semua", "%.2f")
    sliderRow("sx", "Width", "%.2f")
    sliderRow("sy", "Height", "%.2f")
    sliderRow("sz", "Depth", "%.2f")

    hdr("ARAH")
    do
        local f = mk("Frame", {Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1, LayoutOrder = bn()}, block)
        mk("UIGridLayout", {CellSize = UDim2.new(1 / 3, -4, 0, 26), CellPadding = UDim2.new(0, 5, 0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, f)
        for _, d in ipairs({{"LEFT", "px", -1}, {"RIGHT", "px", 1}, {"UP", "py", 1}, {"DOWN", "py", -1}, {"FRONT", "pz", 1}, {"BACK", "pz", -1}}) do
            local b = btn(f, d[1], nil, nil, nil, 10)
            b.MouseButton1Click:Connect(function() DZ.Pos.set(d[2], DZ.Pos.get(d[2]) + d[3] * UI.step) end)
        end
        local stepB = btn(block, "Langkah arah: 0.05", nil, nil, UDim2.new(1, 0, 0, 24), 10)
        stepB.LayoutOrder = bn()
        local steps, si = {0.01, 0.05, 0.1, 0.25, 0.5}, 2
        stepB.MouseButton1Click:Connect(function()
            si = si % #steps + 1
            UI.step = steps[si]
            stepB.Text = "Langkah arah: " .. tostring(UI.step)
        end)
    end
    do
        local f = mk("Frame", {Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1, LayoutOrder = bn()}, block)
        mk("UIGridLayout", {CellSize = UDim2.new(0.5, -3, 0, 26), CellPadding = UDim2.new(0, 5, 0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, f)
        for _, d in ipairs({{"Reset Position", "pos"}, {"Reset Rotation", "rot"}, {"Reset Scale", "scale"}, {"Reset All", "all"}}) do
            local b = btn(f, d[1], "danger", nil, nil, 10)
            b.MouseButton1Click:Connect(function() DZ.Pos.reset(d[2]) DZ.log("Reset: " .. d[1]) end)
        end
        local f2 = mk("Frame", {Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = bn()}, block)
        mk("UIGridLayout", {CellSize = UDim2.new(0.5, -3, 0, 26), CellPadding = UDim2.new(0, 5, 0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, f2)
        local sv = btn(f2, "Simpan Posisi", "accent", nil, nil, 10)
        local rs = btn(f2, "Pulihkan Posisi", nil, nil, nil, 10)
        sv.MouseButton1Click:Connect(function()
            DZ.log(DZ.Pos.save() and "Posisi item disimpan." or "Pilih item yang sedang dipakai dulu.")
        end)
        rs.MouseButton1Click:Connect(function()
            DZ.log(DZ.Pos.restore() and "Posisi tersimpan dipulihkan." or "Belum ada posisi tersimpan untuk item ini.")
        end)
    end

    function UI.edRefresh()
        local id = DZ.Pos.sel
        local e = id and S.worn[id]
        local ok = e ~= nil and e.kind == "Acc"
        lock.Visible = not ok
        selLbl.Text = ok and ("Item dipilih: " .. tostring(e.name) .. " (#" .. tostring(id) .. ")") or "Item dipilih: -"
        tgtLbl.Text = "Preview: " .. DZ.targetLabel(DZ.cur) .. (DZ.cur.kind ~= "me" and "  (draft)" or "")
        for _, u in ipairs(updaters) do u() end
    end

    function UI.edChips()
        for _, c in ipairs(chips:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local any = false
        for _, e in ipairs(DZ.wornList()) do
            if e.kind == "Acc" then
                any = true
                local b = btn(chips, tostring(e.name), nil, nil, UDim2.new(0, 104, 1, -4), 9)
                b.TextTruncate = Enum.TextTruncate.AtEnd
                if DZ.Pos.sel == e.id then accPaint(b, "BackgroundColor3") end
                b.MouseButton1Click:Connect(function() DZ.Pos.select(e.id) end)
            end
        end
        if not any then
            DZ.Pos.sel = nil
        elseif not (DZ.Pos.sel and S.worn[DZ.Pos.sel]) then
            for _, e in ipairs(DZ.wornList()) do
                if e.kind == "Acc" then DZ.Pos.sel = e.id break end
            end
        end
    end

    UI.pages.editor = {frame = page, onShow = function()
        UI.edChips()
        UI.edRefresh()
        Pv.dirty = true
    end}
end

-- ================= WARDROBE + PRESET =================
do
    local page = mk("Frame", {Name = "wardrobe", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false}, content)
    local W_ = {mode = "item"}
    local tabItem = btn(page, "Item", "accent", UDim2.new(0, 0, 0, 0), UDim2.new(0, 80, 0, 26), 10)
    local tabPre = btn(page, "Preset", nil, UDim2.new(0, 86, 0, 0), UDim2.new(0, 80, 0, 26), 10)
    local rmAll = btn(page, "Lepas Semua", "danger", UDim2.new(1, -100, 0, 0), UDim2.new(0, 100, 0, 26), 10)
    local who = txt(page, "", 10, C.gray, {Position = UDim2.new(0, 174, 0, 0), Size = UDim2.new(1, -282, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd})

    local list = scroller(page, UDim2.new(0, 0, 0, 32), UDim2.new(1, 0, 1, -32))
    mk("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, list)

    local function clearList()
        for _, c in ipairs(list:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end
    end

    local function itemRow(e, n)
        local r = corner(mk("Frame", {BackgroundColor3 = C.card, Size = UDim2.new(1, -6, 0, 76), LayoutOrder = n, BorderSizePixel = 0}, list), 10)
        lstroke(r, C.line, 1, 0)
        local tb = corner(mk("Frame", {Position = UDim2.new(0, 6, 0, 6), Size = UDim2.new(0, 42, 0, 42), BackgroundColor3 = C.black, BorderSizePixel = 0}, r), 8)
        mk("ImageLabel", {
            Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
            Image = "rbxthumb://type=Asset&id=" .. tostring(e.id) .. "&w=150&h=150",
        }, tb)
        txt(r, tostring(e.name), 11, C.white, {Font = FONT_B, Position = UDim2.new(0, 56, 0, 7), Size = UDim2.new(1, -140, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd})
        txt(r, "#" .. tostring(e.id) .. " | " .. tostring(e.cat or "-") .. " | " .. tostring(e.kind), 9, C.gray, {Position = UDim2.new(0, 56, 0, 26), Size = UDim2.new(1, -66, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd})
        local badge = corner(txt(r, DZ.cur.kind == "me" and "EQUIPPED" or "DRAFT", 8, C.white, {
            Font = FONT_B, BackgroundTransparency = 0, BackgroundColor3 = DZ.cur.kind == "me" and C.green or C.gold,
            TextColor3 = DZ.cur.kind == "me" and C.white or GOLD_TXT,
            Position = UDim2.new(1, -72, 0, 8), Size = UDim2.new(0, 64, 0, 16), TextXAlignment = Enum.TextXAlignment.Center,
        }, r), 8)
        local isAcc = e.kind == "Acc"
        local b1 = btn(r, "EDIT", isAcc and "accent" or nil, UDim2.new(0, 6, 1, -28), UDim2.new(0.34, -8, 0, 22), 10)
        local b2 = btn(r, "REMOVE", "danger", UDim2.new(0.34, 0, 1, -28), UDim2.new(0.33, -4, 0, 22), 10)
        local b3 = btn(r, "RESET POS", nil, UDim2.new(0.67, 0, 1, -28), UDim2.new(0.33, -8, 0, 22), 9)
        b1.MouseButton1Click:Connect(function()
            if not isAcc then DZ.log("Pakaian / wajah / body part tidak punya posisi untuk diedit.") return end
            DZ.Pos.select(e.id)
            UI.show("editor")
        end)
        b2.MouseButton1Click:Connect(function()
            DZ.unwear(e.id)
            DZ.repaint()
            DZ.log("Dilepas: " .. tostring(e.name))
        end)
        b3.MouseButton1Click:Connect(function()
            if not isAcc then DZ.log("Item ini tidak punya posisi.") return end
            local keep = DZ.Pos.sel
            DZ.Pos.sel = e.id
            DZ.Pos.reset("all")
            DZ.Pos.sel = keep
            DZ.log("Posisi direset: " .. tostring(e.name))
        end)
    end

    local presetName = ""

    function W_.refresh()
        clearList()
        who.Text = "Target: " .. DZ.targetLabel(DZ.cur)
        if W_.mode == "item" then accPaint(tabItem, "BackgroundColor3") accObjs[tabPre] = nil tabPre.BackgroundColor3 = C.glass
        else accPaint(tabPre, "BackgroundColor3") accObjs[tabItem] = nil tabItem.BackgroundColor3 = C.glass end
        rmAll.Visible = W_.mode == "item"
        local n = 0
        if W_.mode == "item" then
            for _, e in ipairs(DZ.wornList()) do
                n = n + 1
                itemRow(e, n)
            end
            if n == 0 then
                local l = para(list, "Belum ada item yang dipakai.\nPakai item dari Katalog / Aksesoris / Pakaian.", 10)
                l.LayoutOrder = 1
            end
            return
        end
        local row = mk("Frame", {Size = UDim2.new(1, -6, 0, 30), BackgroundTransparency = 1, LayoutOrder = 1}, list)
        local box = mk("TextBox", {
            Size = UDim2.new(1, -92, 1, 0), BackgroundColor3 = C.glass, PlaceholderText = "Nama preset...", PlaceholderColor3 = C.gray,
            Text = presetName, TextColor3 = C.white, Font = FONT, TextSize = 11, ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0,
        }, row)
        corner(box, 8)
        lstroke(box, C.white, 1, 0.88)
        mk("UIPadding", {PaddingLeft = UDim.new(0, 10)}, box)
        local save = btn(row, "Simpan", "accent", UDim2.new(1, -86, 0, 0), UDim2.new(0, 86, 1, 0), 11)
        box:GetPropertyChangedSignal("Text"):Connect(function() presetName = box.Text end)
        save.MouseButton1Click:Connect(function()
            local nm = trim(box.Text)
            if nm == "" then DZ.log("Isi nama preset dulu.") return end
            DZ.presetSave(nm)
            DZ.log("Preset disimpan: " .. nm .. (DZ.Storage.canFS and "" or " (hanya sesi ini, executor tanpa writefile)"))
            W_.refresh()
        end)
        local names = {}
        for k in pairs(DZ.presets) do names[#names + 1] = k end
        table.sort(names)
        n = 1
        for _, nm in ipairs(names) do
            n = n + 1
            local p = DZ.presets[nm]
            local r = corner(mk("Frame", {BackgroundColor3 = C.card, Size = UDim2.new(1, -6, 0, 48), LayoutOrder = n, BorderSizePixel = 0}, list), 10)
            lstroke(r, C.line, 1, 0)
            local cnt = (type(p) == "table" and type(p.items) == "table") and #p.items or 0
            txt(r, tostring(nm), 11, C.white, {Font = FONT_B, Position = UDim2.new(0, 10, 0, 7), Size = UDim2.new(1, -140, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd})
            txt(r, tostring(cnt) .. " item", 9, C.gray, {Position = UDim2.new(0, 10, 0, 25), Size = UDim2.new(1, -140, 0, 12)})
            local ld = btn(r, "Load", "accent", UDim2.new(1, -128, 0.5, -12), UDim2.new(0, 58, 0, 24), 10)
            local dl = btn(r, "Hapus", "danger", UDim2.new(1, -64, 0.5, -12), UDim2.new(0, 58, 0, 24), 10)
            ld.MouseButton1Click:Connect(function()
                DZ.log(DZ.presetLoad(nm) and ("Memuat preset: " .. nm) or "Preset tidak valid.")
            end)
            dl.MouseButton1Click:Connect(function()
                UI.confirm("Hapus preset \"" .. nm .. "\"?", function()
                    DZ.presetDelete(nm)
                    W_.refresh()
                end)
            end)
        end
        if #names == 0 then
            local pl = para(list, "Belum ada preset. Pakai item lalu beri nama dan tekan Simpan.", 10)
            pl.LayoutOrder = 99
        end
    end

    tabItem.MouseButton1Click:Connect(function() W_.mode = "item" W_.refresh() end)
    tabPre.MouseButton1Click:Connect(function() W_.mode = "preset" W_.refresh() end)
    rmAll.MouseButton1Click:Connect(function()
        if next(S.worn) == nil then return end
        UI.confirm("Lepas semua item pada " .. DZ.targetLabel(DZ.cur) .. "?", function()
            for id in pairs(S.worn) do DZ.unwear(id) end
            DZ.repaint()
            DZ.log("Semua item dilepas.")
        end)
    end)
    UI.wardrobe = W_
    UI.pages.wardrobe = {frame = page, onShow = W_.refresh}
end

-- ================= FRIEND / TEMAN =================
do
    local PER = 4
    local FP = {page = 1}
    local page = mk("Frame", {Name = "friend", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false}, content)
    txt(page, "FRIEND / TEMAN", 12, C.white, {Font = FONT_B, Position = UDim2.new(0, 2, 0, 0), Size = UDim2.new(1, -160, 0, 24)})
    local up = btn(page, "\226\150\178", nil, UDim2.new(1, -118, 0, 0), UDim2.new(0, 30, 0, 24), 10)
    local pl = txt(page, "Page 1 / 1", 10, C.gray, {Font = FONT_B, Position = UDim2.new(1, -86, 0, 0), Size = UDim2.new(0, 56, 0, 24), TextXAlignment = Enum.TextXAlignment.Center})
    local dn = btn(page, "\226\150\188", nil, UDim2.new(1, -30, 0, 0), UDim2.new(0, 30, 0, 24), 10)

    local hold = mk("Frame", {Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, PER * 54), BackgroundTransparency = 1, ClipsDescendants = true}, page)
    local list = mk("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1}, hold)

    local ST_COL = {Empty = C.gray, Selected = C.white, ["Belum di-Apply"] = C.gold, Applied = C.green, Offline = C.red}

    local function pages() return math.max(1, math.ceil(#DZ.slots / PER)) end

    local function buildRows()
        for _, c in ipairs(list:GetChildren()) do c:Destroy() end
        local first = (FP.page - 1) * PER
        for k = 1, PER do
            local i = first + k
            local s = DZ.slots[i]
            if not s then break end
            local t = s.t
            local row = corner(mk("Frame", {Position = UDim2.new(0, 0, 0, (k - 1) * 54), Size = UDim2.new(1, -2, 0, 50), BackgroundColor3 = C.card, BorderSizePixel = 0}, list), 10)
            local rs = lstroke(row, C.line, 1, 0)
            if t and DZ.cur == t then
                accPaint(rs, "Color")
                rs.Thickness = 1.5
            end
            local av = corner(mk("ImageLabel", {
                Position = UDim2.new(0, 7, 0, 5), Size = UDim2.new(0, 40, 0, 40), BackgroundColor3 = C.black, BorderSizePixel = 0,
                Image = t and ("rbxthumb://type=AvatarHeadShot&id=" .. tostring(t.userId) .. "&w=150&h=150") or "",
            }, row), 20)
            if not t then
                txt(av, "+", 18, C.gray, {Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, Font = FONT_B})
            end
            txt(row, t and tostring(t.display) or ("Friend Slot " .. i), 11, C.white, {
                Font = FONT_B, Position = UDim2.new(0, 56, 0, 7), Size = UDim2.new(1, -250, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd,
            })
            local status = DZ.friendStatus(t)
            txt(row, "Slot " .. i .. "  |  " .. status, 9, ST_COL[status] or C.gray, {
                Font = FONT_B, Position = UDim2.new(0, 56, 0, 26), Size = UDim2.new(1, -250, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd,
            })
            local selB = mk("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, -196, 1, 0)}, row)
            selB.MouseButton1Click:Connect(function()
                if t then
                    DZ.setTarget(t)
                    DZ.log("Mengedit " .. DZ.targetLabel(t))
                else
                    UI.pickPlayer(i, function() UI.friendRefresh() end)
                end
            end)
            local b1 = btn(row, t and "Ganti" or "Pilih", t and nil or "accent", UDim2.new(1, -190, 0.5, -12), UDim2.new(0, 56, 0, 24), 10)
            local b2 = btn(row, "Edit", t and "accent" or nil, UDim2.new(1, -128, 0.5, -12), UDim2.new(0, 56, 0, 24), 10)
            local b3 = btn(row, "Clear", "danger", UDim2.new(1, -66, 0.5, -12), UDim2.new(0, 58, 0, 24), 10)
            b1.MouseButton1Click:Connect(function()
                UI.pickPlayer(i, function() UI.friendRefresh() end)
            end)
            b2.MouseButton1Click:Connect(function()
                if not t then
                    UI.pickPlayer(i, function() UI.friendRefresh() end)
                    return
                end
                DZ.setTarget(t)
                DZ.log("Mengedit " .. DZ.targetLabel(t) .. ": pilih item, lalu tekan APPLY.")
                UI.show("acc")
            end)
            b3.MouseButton1Click:Connect(function()
                if not t then return end
                UI.confirm("Kosongkan Slot " .. i .. " dan hapus perubahan untuk " .. tostring(t.display) .. "?", function()
                    DZ.clearSlot(i)
                    UI.friendRefresh()
                end)
            end)
        end
    end

    -- dir: -1 / 1 untuk animasi geser antar-page
    function UI.friendRefresh(dir)
        FP.page = math.clamp(FP.page, 1, pages())
        pl.Text = "Page " .. FP.page .. " / " .. pages()
        up.TextTransparency = FP.page > 1 and 0 or 0.6
        dn.TextTransparency = FP.page < pages() and 0 or 0.6
        buildRows()
        if dir then
            list.Position = UDim2.new(0, 0, 0, dir * 28)
            tween(list, 0.22, {Position = UDim2.new(0, 0, 0, 0)}, Enum.EasingStyle.Quint)
        end
    end

    up.MouseButton1Click:Connect(function()
        if FP.page > 1 then FP.page = FP.page - 1 UI.friendRefresh(-1) end
    end)
    dn.MouseButton1Click:Connect(function()
        if FP.page < pages() then FP.page = FP.page + 1 UI.friendRefresh(1) end
    end)

    local bottom = mk("Frame", {Position = UDim2.new(0, 0, 0, 30 + PER * 54 + 4), Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1}, page)
    mk("UIGridLayout", {CellSize = UDim2.new(0.25, -5, 0, 28), CellPadding = UDim2.new(0, 6, 0, 0), SortOrder = Enum.SortOrder.LayoutOrder}, bottom)
    local addB = btn(bottom, "+ Add Slot", nil, nil, nil, 10)
    local pvB = btn(bottom, "Preview 3D", nil, nil, nil, 10)
    local apB = btn(bottom, "APPLY", "accent", nil, nil, 10)
    local rsB = btn(bottom, "RESET", "danger", nil, nil, 10)
    addB.LayoutOrder, pvB.LayoutOrder, apB.LayoutOrder, rsB.LayoutOrder = 1, 2, 3, 4
    addB.MouseButton1Click:Connect(function()
        DZ.addSlot()
        FP.page = pages()
        UI.friendRefresh(1)
        DZ.log("Slot ditambah (total " .. #DZ.slots .. ").")
    end)
    pvB.MouseButton1Click:Connect(function()
        if DZ.cur.kind == "me" then DZ.log("Pilih slot Friend dulu.") return end
        UI.show("editor")
    end)
    apB.MouseButton1Click:Connect(function()
        local t = DZ.cur
        if t.kind == "me" then DZ.log("Pilih slot Friend dulu (klik slot / Edit).") return end
        local ok, err = DZ.friendApply(t)
        DZ.log(ok and ("Apply ke " .. tostring(t.display) .. " berhasil (visual lokal).") or ("Apply gagal: " .. tostring(err)))
        UI.friendRefresh()
    end)
    rsB.MouseButton1Click:Connect(function()
        local t = DZ.cur
        if t.kind == "me" then DZ.log("Pilih slot Friend dulu.") return end
        UI.confirm("Hapus SEMUA perubahan untuk " .. tostring(t.display) .. "?", function()
            DZ.friendReset(t)
            UI.friendRefresh()
        end)
    end)

    UI.pages.friend = {frame = page, onShow = function() UI.friendRefresh() end}
end

-- ================= SETELAN =================
do
    local page = mk("Frame", {Name = "settings", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false}, content)
    local sc = scroller(page, UDim2.new(), UDim2.new(1, 0, 1, 0))
    mk("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, sc)
    local o = 0
    local function setting(text, key)
        o = o + 1
        local b = btn(sc, "", nil, nil, UDim2.new(1, -6, 0, 30), 10)
        b.LayoutOrder = o
        local function paint()
            b.Text = text .. (S.settings[key] and "   [ON]" or "   [OFF]")
            if S.settings[key] then accPaint(b, "BackgroundColor3") else accObjs[b] = nil b.BackgroundColor3 = C.glass end
        end
        paint()
        b.MouseButton1Click:Connect(function()
            S.settings[key] = not S.settings[key]
            DZ.Storage.save("settings", S.settings)
            paint()
        end)
    end
    setting("Auto re-apply (rig Evade)", "reapply")
    setting("Ganti item di slot yang sama", "replaceSlot")
    local function act(text, fn)
        o = o + 1
        local b = btn(sc, text, nil, nil, UDim2.new(1, -6, 0, 30), 10)
        b.LayoutOrder = o
        b.MouseButton1Click:Connect(fn)
    end
    act("Bersihkan cache katalog", function() DZ.Cat.clear() DZ.log("Cache katalog dibersihkan.") end)
    act("Hapus riwayat percobaan", function()
        S.history = {}
        DZ.Storage.save("history", S.history)
        DZ.log("Riwayat dihapus.")
    end)
    o = o + 1
    local info = para(sc,
        "PENYIMPANAN: " .. (DZ.Storage.canFS and "file lokal (writefile) aktif" or "writefile tidak tersedia: Favorit/preset hanya bertahan selama sesi") ..
        "\n\nKETERBATASAN:\n" ..
        "- Semua visual & lokal. Tidak mengubah inventory, tidak membeli, tidak memberi Limited. Pemain lain umumnya tidak melihat perubahan.\n" ..
        "- Friend: hanya pemain yang ada di server. Perubahan teman memakai draft sendiri dan baru dipasang saat APPLY. Data slot tidak disimpan setelah UI ditutup.\n" ..
        "- Status Limited / Limited U dari MarketplaceService; jika gagal tampil Unknown. Label Collectible berasal dari filter koleksi Roblox.\n" ..
        "- Layered clothing & sepatu dipasang kaku (tidak mengikuti bentuk tubuh).\n" ..
        "- Body part (kepala, badan, lengan, kaki) berupa overlay MeshPart di R15 dan R6; asset R15 di rig R6 disesuaikan otomatis, asset R6 klasik tidak bisa di R15 murni; hasil bisa berbeda tiap asset.\n" ..
        "- Ear / Eye / Head / Other tidak punya tipe asset resmi, jadi difilter dengan kata kunci.\n" ..
        "- Posisi/rotasi/skala hanya untuk aksesori.\n" ..
        "- Preview 3D memakai salinan karakter; bisa tidak tersedia di rig yang tidak bisa di-clone.", 9)
    info.LayoutOrder = o
    UI.pages.settings = {frame = page}
end

-- ================= HOME =================
do
    local page = mk("Frame", {Name = "home", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false}, content)
    local sc = scroller(page, UDim2.new(), UDim2.new(1, 0, 1, 0))
    mk("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, sc)
    local t = txt(sc, "DZ AVATAR CATALOG", 18, C.white, {Font = FONT_B, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1})
    local s2 = txt(sc, "ULTIMATE  |  DELUX ZEPHYR", 10, C.gold, {Font = FONT_B, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 2})
    local card = corner(mk("Frame", {Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.card, LayoutOrder = 3, BorderSizePixel = 0}, sc), 10)
    lstroke(card, C.line, 1, 0)
    mk("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, card)
    local stats = para(card, "", 10, C.white)
    local grid = mk("Frame", {Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4}, sc)
    mk("UIGridLayout", {CellSize = UDim2.new(0.25, -6, 0, 32), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, grid)
    local quick = {
        {"Katalog", "catalog"}, {"Aksesoris", "acc"}, {"Pakaian", "clo"}, {"Body", "body"},
        {"Limited", "ltd"}, {"Favorit", "fav"}, {"Editor", "editor"}, {"Friend", "friend"},
    }
    for i, q in ipairs(quick) do
        local b = btn(grid, q[1], q[2] == "ltd" and "gold" or (i == 1 and "accent" or nil), nil, nil, 11)
        b.LayoutOrder = i
        b.MouseButton1Click:Connect(function() UI.show(q[2]) end)
    end
    local note = para(sc, "Semua fitur bersifat visual & lokal: tidak mengubah inventory akun, tidak membeli, dan tidak memberi item Limited. Perubahan tidak otomatis terlihat pemain lain.", 9)
    note.LayoutOrder = 5

    function UI.homeUpdate()
        local c = DZ.curChar()
        local n = 0
        for _ in pairs(S.worn) do n = n + 1 end
        local nf = 0
        for _, s in ipairs(DZ.slots) do if s.t then nf = nf + 1 end end
        stats.Text = "Target: " .. DZ.targetLabel(DZ.cur) ..
            "\nRig: " .. (c and DZ.rigDetail(c) or "belum ketemu") ..
            "\nItem dipakai: " .. tostring(n) .. "   |   Favorit: " .. tostring(#DZ.Fav.list) ..
            "\nSlot Friend terisi: " .. tostring(nf) .. " / " .. tostring(#DZ.slots) ..
            "\nPenyimpanan: " .. (DZ.Storage.canFS and "file lokal" or "sesi saja")
    end
    UI.pages.home = {frame = page, onShow = UI.homeUpdate}
end

-- ================= NAVIGASI =================
function UI.show(name)
    local p = UI.pages[name]
    if not p then return end
    UI.current = name
    for k, q in pairs(UI.pages) do q.frame.Visible = (k == name) end
    p.frame.Position = UDim2.new(0, 14, 0, 0)
    tween(p.frame, 0.22, {Position = UDim2.new(0, 0, 0, 0)}, Enum.EasingStyle.Quint)
    for k, b in pairs(UI.nav) do
        if k == name then
            if k == "ltd" then accObjs[b] = nil b.BackgroundColor3 = C.gold b.TextColor3 = GOLD_TXT
            else accPaint(b, "BackgroundColor3") b.TextColor3 = C.white end
        else
            accObjs[b] = nil
            b.BackgroundColor3 = C.glass
            b.TextColor3 = C.gray
        end
    end
    DZ.Prev.visible = (name == "editor")
    if DZ.Prev.visible then DZ.Prev.dirty = true end
    if p.onShow then pcall(p.onShow) end
end
accHooks[#accHooks + 1] = function() if UI.current then UI.show(UI.current) end end

DZ.repaint = function()
    UI.paintAll()
    pcall(UI.bodyPaint)
    if UI.edChips then UI.edChips() end
    if UI.edRefresh then UI.edRefresh() end
    UI.layout()
    UI.bannerUpdate()
    local cur = UI.pages[UI.current]
    if UI.current == "wardrobe" and UI.wardrobe then UI.wardrobe.refresh() end
    if UI.current == "friend" then UI.friendRefresh() end
    if UI.current == "home" then pcall(UI.homeUpdate) end
    if cur and cur.isWornTab and cur.isWornTab() then cur.search() end
    if cur and cur.refreshCustom then cur.refreshCustom() end
end

DZ.onTarget = function()
    UI.layout()
    UI.bannerUpdate()
end

local function cleanup()
    S.alive = false
    pcall(DZ.Prev.setSpin, false)
    pcall(DZ.cleanupAll)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if UI.embedded then
        pcall(function() root:Destroy() end)
    else
        pcall(function() gui:Destroy() end)
    end
    if _G.DZ_CATALOG_CLEAN == cleanup then _G.DZ_CATALOG_CLEAN = nil end
end
_G.DZ_CATALOG_CLEAN = cleanup

if not UI.embedded then
    UI.clsB.MouseButton1Click:Connect(cleanup)
    local minimized = false
    UI.minB.MouseButton1Click:Connect(function()
        minimized = not minimized
        root.Visible = not minimized
        UI.main.Size = minimized and UDim2.new(0, UI.WIN[1], 0, 30) or UDim2.new(0, UI.WIN[1], 0, UI.WIN[2])
    end)
end

-- loop ringan 0.4 detik: status bar + rebuild preview bila perlu (bukan Heartbeat)
task.spawn(function()
    while S.alive do
        local c = DZ.curChar()
        local n = 0
        for _ in pairs(S.worn) do n = n + 1 end
        local lbl = DZ.targetLabel(DZ.cur)
        rigLbl.Text = c and (lbl .. " | " .. DZ.rigDetail(c) .. " | " .. tostring(n) .. " item") or (lbl .. " | karakter belum ketemu")
        if DZ.Prev.visible and DZ.Prev.dirty and DZ.Prev.wm then
            DZ.Prev.dirty = false
            pcall(DZ.Prev.rebuild)
        end
        if UI.current == "home" then pcall(UI.homeUpdate) end
        task.wait(0.4)
    end
end)

UI.layout()
UI.show("home")
DZ.log("DZ Avatar Catalog siap.")
if HOST and type(HOST.ready) == "function" then pcall(HOST.ready, {cleanup = cleanup}) end
