local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local PS=game:GetService("PhysicsService")
local Debris=game:GetService("Debris")
local Tween=game:GetService("TweenService")
local tool=script.Parent

local C={dano=15,intervalo=1,durAnim=.45,tempoRagdoll=1,empurraTras=55,empurraCima=30,alcance=14,efeito=true,tremorAtivo=true,tremorAtk=.65,tremorVit=1.1,tremorDur=.22,somVentoVol=2.5,somVentoDist=45,somImpactoId="rbxassetid://9118823728",somImpactoVol=1.1}
local PERNAS={["Left Leg"]=1,["Right Leg"]=1}
local JOINTS={["Left Shoulder"]=1,["Right Shoulder"]=1,["Left Hip"]=1,["Right Hip"]=1,RootJoint=1}
local atacando,equipado,ultimo,mapa,charAtual=false,false,0,nil,nil

pcall(function()
	PS:RegisterCollisionGroup("Ragdoll")
	PS:CollisionGroupSetCollidable("Ragdoll","Ragdoll",false)
end)

local seqClick=tool:FindFirstChild("Click",true)
if not seqClick then warn("[Tool] Click não encontrada.") end

local remoteFX=RS:FindFirstChild("CombatFX")
if not remoteFX or not remoteFX:IsA("RemoteEvent") then
	if remoteFX then remoteFX:Destroy() end
	remoteFX=Instance.new("RemoteEvent")
	remoteFX.Name="CombatFX"
	remoteFX.Parent=RS
end

local function novaPart(cf,size,mat,color,trans)
	local p=Instance.new("Part")
	p.Anchored=true
	p.CanCollide=false
	p.CanQuery=false
	p.CanTouch=false
	p.Size=size
	p.Material=mat
	p.Color=color
	p.Transparency=trans
	p.CFrame=cf
	p.Parent=workspace
	return p
end

local function mapaMotores(p)
	local m={}
	for _,o in ipairs(p:GetDescendants()) do
		if o:IsA("Motor6D") and o.Part1 then
			m[o.Part1.Name]=m[o.Part1.Name] or {}
			table.insert(m[o.Part1.Name],o)
		end
	end
	return m
end

local function acharMotor(m,pose)
	local c=m[pose.Name]
	if not c then return end
	if #c==1 then return c[1] end
	local pai=pose.Parent and pose.Parent:IsA("Pose") and pose.Parent.Name
	for _,mo in ipairs(c) do
		if pai and mo.Part0 and mo.Part0.Name==pai then return mo end
	end
	return c[1]
end

local function baseC0(mo)
	local t=mo:FindFirstChild("BaseC0Original")
	if not t then
		t=Instance.new("CFrameValue")
		t.Name="BaseC0Original"
		t.Value=mo.C0
		t.Parent=mo
	end
	return t.Value
end

local cache={}
local function kfs(seq)
	if cache[seq] then return cache[seq] end
	local k=seq:GetKeyframes()
	table.sort(k,function(a,b)return a.Time<b.Time end)
	local d=#k>0 and k[#k].Time or 1
	if d<=0 then d=1 end
	cache[seq]={k=k,d=d}
	return cache[seq]
end

local function limparPoses(p)
	for _,o in ipairs(p:GetDescendants()) do
		if o:IsA("Motor6D") then
			local t=o:FindFirstChild("BaseC0Original")
			if t then o.C0=t.Value;t:Destroy() end
		end
	end
end

local function tocarClick(m,seq,dur)
	if not seq then return end
	local d=kfs(seq)
	if #d.k==0 then return end
	local esc=dur/d.d
	local iniciais={}

	for i,kf in ipairs(d.k) do
		local ds=d.k[i+1] and (d.k[i+1].Time-kf.Time)*esc or 0
		local metas={}
		for _,pose in ipairs(kf:GetDescendants()) do
			if pose:IsA("Pose") and not PERNAS[pose.Name] then
				local mo=acharMotor(m,pose)
				if mo then
					iniciais[mo]=iniciais[mo] or baseC0(mo)
					table.insert(metas,{mo,iniciais[mo]*pose.CFrame,Enum.EasingStyle[pose.EasingStyle.Name] or Enum.EasingStyle.Linear,Enum.EasingDirection[pose.EasingDirection.Name] or Enum.EasingDirection.Out})
				end
			end
		end
		if ds>0 then
			for _,x in ipairs(metas) do
				if x[1].Parent then Tween:Create(x[1],TweenInfo.new(ds,x[3],x[4]),{C0=x[2]}):Play() end
			end
			task.wait(ds)
		else
			for _,x in ipairs(metas) do
				if x[1].Parent then x[1].C0=x[2] end
			end
		end
	end

	local tw={}
	for mo,orig in pairs(iniciais) do
		if mo and mo.Parent then
			local t=Tween:Create(mo,TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{C0=orig})
			t:Play()
			table.insert(tw,t)
		end
	end
	if #tw>0 then tw[#tw].Completed:Wait() end
end

local function trailHandle(h)
	if not h then return end
	local t=h:FindFirstChild("AttackTrail")
	if t then return t end

	local a1=Instance.new("Attachment",h)
	a1.Name="TrailA1"
	a1.Position=Vector3.new(0,0,-h.Size.Z/2)

	local a2=Instance.new("Attachment",h)
	a2.Name="TrailA2"
	a2.Position=Vector3.new(0,0,h.Size.Z/2)

	t=Instance.new("Trail")
	t.Name="AttackTrail"
	t.Attachment0=a1
	t.Attachment1=a2
	t.Color=ColorSequence.new(Color3.new(1,1,1))
	t.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,1)})
	t.WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,.15)})
	t.Lifetime=.28
	t.LightEmission=.6
	t.Enabled=false
	t.Parent=h
	return t
end

local function piscarTrail(h,dur)
	local t=trailHandle(h)
	if not t then return end
	t.Enabled=true
	task.delay(dur,function()
		if t and t.Parent then t.Enabled=false end
	end)
end

local function somVento(pos)
	local mod=RS:FindFirstChild("Vento",true)
	if not mod then return end
	local s
	if mod:IsA("Sound") then
		s=mod:Clone()
	elseif mod:IsA("Model") or mod:IsA("Folder") then
		local x=mod:FindFirstChildWhichIsA("Sound",true)
		if x then s=x:Clone() end
	end
	if not s then return end
	local p=novaPart(CFrame.new(pos),Vector3.new(.2,.2,.2),Enum.Material.Plastic,Color3.new(1,1,1),1)
	p.Name="ImpactSound"
	s.Volume=C.somVentoVol
	s.RollOffMaxDistance=C.somVentoDist
	s.Parent=p
	s:Play()
	Debris:AddItem(p,math.max(s.TimeLength+.5,2))
end

local function pop(pos)
	local mod=RS:FindFirstChild("Pop",true)
	if not mod or not mod:IsA("Model") then return false end
	local c=mod:Clone()
	c:PivotTo(CFrame.new(pos))
	c.Parent=workspace
	return true
end

local function tremor(p,int)
	if C.tremorAtivo and p and p:IsA("Player") then
		remoteFX:FireClient(p,"HitShake",{intensidade=int or C.tremorAtk,duracao=C.tremorDur})
	end
end

local function efeito(pos,dir)
	dir=(dir and dir.Magnitude>.001) and dir.Unit or Vector3.new(0,0,1)
	local base=novaPart(CFrame.lookAt(pos,pos+dir),Vector3.new(.2,.2,.2),Enum.Material.Plastic,Color3.new(1,1,1),1)
	base.Name="ImpactBase"

	local luz=Instance.new("PointLight")
	luz.Color=Color3.fromRGB(255,250,235)
	luz.Brightness=14
	luz.Range=18
	luz.Parent=base

	task.spawn(function()
		for i=1,12 do
			if not luz.Parent then return end
			luz.Brightness=14*(1-i/12)
			task.wait(.016)
		end
		luz:Destroy()
	end)

	local onda=novaPart(CFrame.new(pos),Vector3.new(.5,.5,.5),Enum.Material.Neon,Color3.new(1,1,1),.15)
	onda.Shape=Enum.PartType.Ball
	Tween:Create(onda,TweenInfo.new(.28,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=Vector3.new(7,7,7),Transparency=1}):Play()
	Debris:AddItem(onda,.4)

	task.delay(.05,function()
		if not base.Parent then return end
		local o=novaPart(CFrame.new(pos),Vector3.new(.4,.4,.4),Enum.Material.Neon,Color3.fromRGB(200,225,255),.35)
		o.Shape=Enum.PartType.Ball
		Tween:Create(o,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(5,5,5),Transparency=1}):Play()
		Debris:AddItem(o,.45)
	end)

	local anel=novaPart(CFrame.new(pos-Vector3.new(0,1,0))*CFrame.Angles(0,0,math.rad(90)),Vector3.new(.15,.5,.5),Enum.Material.Neon,Color3.new(1,1,1),.25)
	anel.Shape=Enum.PartType.Cylinder
	Tween:Create(anel,TweenInfo.new(.35,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=Vector3.new(.15,9,9),Transparency=1}):Play()
	Debris:AddItem(anel,.45)

	local sp=Instance.new("ParticleEmitter")
	sp.Texture="rbxasset://textures/particles/sparks_main.dds"
	sp.Rate=0
	sp.Lifetime=NumberRange.new(.25,.5)
	sp.Speed=NumberRange.new(15,28)
	sp.SpreadAngle=Vector2.new(180,180)
	sp.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)})
	sp.Color=ColorSequence.new(Color3.new(1,1,1))
	sp.LightEmission=1
	sp.Parent=base
	sp:Emit(30)

	local sm=Instance.new("ParticleEmitter")
	sm.Texture="rbxasset://textures/particles/smoke_main.dds"
	sm.Rate=0
	sm.Lifetime=NumberRange.new(.5,.9)
	sm.Speed=NumberRange.new(3,7)
	sm.SpreadAngle=Vector2.new(60,60)
	sm.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.8),NumberSequenceKeypoint.new(1,3)})
	sm.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.5),NumberSequenceKeypoint.new(1,1)})
	sm.Color=ColorSequence.new(Color3.fromRGB(235,235,235))
	sm.Parent=base
	sm:Emit(8)

	for _=1,6 do
		local d=novaPart(CFrame.new(pos),Vector3.new(.12,.12,.12),Enum.Material.Neon,Color3.new(1,1,1),0)
		d.AssemblyLinearVelocity=Vector3.new(math.random(-18,18),math.random(10,22),math.random(-18,18))
		Debris:AddItem(d,.7)
	end

	local s=Instance.new("Sound")
	s.SoundId=C.somImpactoId
	s.Volume=C.somImpactoVol
	s.PlaybackSpeed=math.random(95,118)/100
	s.Parent=base
	s:Play()
	Debris:AddItem(base,1.6)
end

local function empurrar(char,dir)
	dir=dir.Magnitude>0 and dir.Unit or Vector3.zero
	local vel=Vector3.new(dir.X*C.empurraTras,C.empurraCima,dir.Z*C.empurraTras)
	for _,p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then p.AssemblyLinearVelocity=vel end
	end
end

local function ragdoll(p)
	local h=p:FindFirstChildOfClass("Humanoid")
	local root=p:FindFirstChild("HumanoidRootPart")
	if not h or not root or p:GetAttribute("EmRagdoll") then return end

	p:SetAttribute("EmRagdoll",true)
	h.PlatformStand=true
	h.AutoRotate=false
	h:ChangeState(Enum.HumanoidStateType.Physics)

	local anim=p:FindFirstChild("Animate")
	local estava=anim and not anim.Disabled
	if anim then anim.Disabled=true end

	local player=Players:GetPlayerFromCharacter(p)
	if player then
		pcall(function()
			for _,pa in ipairs(p:GetDescendants()) do
				if pa:IsA("BasePart") then pa:SetNetworkOwner(nil) end
			end
		end)
	end

	local criadas,partes={},{}
	for _,o in ipairs(p:GetDescendants()) do
		if o:IsA("Motor6D") and JOINTS[o.Name] and o.Part0 and o.Part1 then
			local a1=Instance.new("Attachment",o.Part0)
			a1.CFrame=o.C0
			local a2=Instance.new("Attachment",o.Part1)
			a2.CFrame=o.C1
			local sk=Instance.new("BallSocketConstraint")
			sk.Attachment0=a1
			sk.Attachment1=a2
			sk.LimitsEnabled=true
			sk.TwistLimitsEnabled=true
			sk.UpperAngle=60
			sk.TwistUpperAngle=40
			sk.TwistLowerAngle=-40
			sk.Parent=o.Part0
			o.Enabled=false
			table.insert(criadas,{mo=o,sk=sk,a1=a1,a2=a2})
		end
	end

	root.CanCollide=false
	for _,pa in ipairs(p:GetDescendants()) do
		if pa:IsA("BasePart") and pa.Name~="HumanoidRootPart" then
			pa.CanCollide=true
			pa.CollisionGroup="Ragdoll"
			table.insert(partes,pa)
		end
	end

	task.delay(C.tempoRagdoll,function()
		if not p or not p.Parent then return end

		for _,d in ipairs(criadas) do
			if d.sk then d.sk:Destroy() end
			if d.a1 then d.a1:Destroy() end
			if d.a2 then d.a2:Destroy() end
			if d.mo then d.mo.Enabled=true end
		end

		for _,pa in ipairs(partes) do
			if pa and pa.Parent then pa.CollisionGroup="Default" end
		end

		if player then
			pcall(function()
				for _,pa in ipairs(p:GetDescendants()) do
					if pa:IsA("BasePart") then pa:SetNetworkOwner(player) end
				end
			end)
		end

		root.CanCollide=true
		if h and h.Parent then
			h.PlatformStand=false
			h.AutoRotate=true
			h:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		if anim then anim.Disabled=not estava end
		p:SetAttribute("EmRagdoll",false)
	end)
end

tool.Equipped:Connect(function()
	local p=tool.Parent
	if not p or not p:IsA("Model") then return end
	equipado=true
	charAtual=p
	mapa=mapaMotores(p)
end)

tool.Unequipped:Connect(function()
	equipado=false
	local p=charAtual
	if p and p.Parent then limparPoses(p) end
	mapa,charAtual=nil,nil
end)

tool.AncestryChanged:Connect(function()
	if not tool.Parent and charAtual then
		equipado,charAtual,mapa=false,nil,nil
	end
end)

tool.Activated:Connect(function()
	if atacando or not equipado or not charAtual or not charAtual.Parent or charAtual:GetAttribute("EmRagdoll") then return end
	local agora=os.clock()
	if agora-ultimo<C.intervalo then return end
	ultimo=agora
	atacando=true

	task.spawn(function()
		local ok,err=pcall(function()
			local p=charAtual
			local m=mapa
			local root=p:FindFirstChild("HumanoidRootPart")
			local handle=tool:FindFirstChild("Handle")
			piscarTrail(handle,C.durAnim)

			local acertados={}
			local conex

			if handle then
				conex=handle.Touched:Connect(function(outra)
					if not outra or not outra:IsA("BasePart") then return end
					local char=outra:FindFirstAncestorOfClass("Model")
					if not char or char==p then return end

					local h=char:FindFirstChildOfClass("Humanoid")
					local r=char:FindFirstChild("HumanoidRootPart")
					if not h or not r or h.Health<=0 or acertados[char] then return end
					if root and (r.Position-root.Position).Magnitude>C.alcance then return end

					acertados[char]=true
					local dir=root and r.Position-root.Position or r.Position-outra.Position
					dir=dir.Magnitude>0 and dir.Unit or Vector3.new(0,0,1)

					local pos=outra.Position
					if not pop(pos) and C.efeito then efeito(pos,dir) end
					somVento(pos)

					local jatk=Players:GetPlayerFromCharacter(p)
					local jvit=Players:GetPlayerFromCharacter(char)
					tremor(jatk,C.tremorAtk)
					if jvit and jvit~=jatk then tremor(jvit,C.tremorVit) end

					empurrar(char,dir)
					ragdoll(char)
					h:TakeDamage(C.dano)
				end)
			end

			tocarClick(m,seqClick,C.durAnim)
			if conex then conex:Disconnect() end
		end)

		if not ok then warn("[Tool] Erro:",err) end
		atacando=false
	end)
end)