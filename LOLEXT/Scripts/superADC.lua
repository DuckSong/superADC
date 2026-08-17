local superADCVersion = "1.0"
local function MaisNova(a, b)
	local pa, pb = {}, {}
	for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
	for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x > y end
	end
	return false
end
do
	local repo = "https://raw.githubusercontent.com/DuckSong/superADC/main"
	local ok = pcall(function()
		local localFile = SCRIPT_PATH .. "superADC.version.remote"
		DownloadFileAsync(repo .. "/superADC.version", localFile, function()
			local h = io.open(localFile, "r")
			if not h then return end
			local remote = (h:read("*l") or ""):gsub("%s+", "")
			h:close()
			if remote ~= "" and MaisNova(remote, superADCVersion) then
			DownloadFileAsync(repo .. "/LOLEXT/Scripts/superADC.lua",
					SCRIPT_PATH .. "superADC.lua", function()
						print("superADC updated to " .. remote .. " -- press F6 twice to reload")
					end)
			end
		end)
	end)
	if not ok then print("superADC: could not check for updates") end
end

pcall(function() require "DamageLib" end)
pcall(function() require "GGPrediction" end)
local VERSAO = superADCVersion
local MathHuge, MathMax, MathMin, MathFloor, MathSqrt, MathAbs =
	math.huge, math.max, math.min, math.floor, math.sqrt, math.abs
local TableInsert = table.insert
local ADC = { Campeao = nil, Modulo = nil }
local LOG_FILE = (SCRIPT_PATH or "") .. "superADC.log"
local _logInicio = nil
local function Log(msg)
	pcall(function()
		local f = io.open(LOG_FILE, _logInicio and "a" or "w")
		if not f then return end
		if not _logInicio then
			_logInicio = true
			f:write("=== superADC | session started ===\n")
		end
		f:write(string.format("[%8.1f] %s\n", Game.Timer(), tostring(msg)))
		f:close()
	end)
	print("superADC: " .. tostring(msg))
end
local _ultimaLinha = {}
local function LogComIntervalo(chave, segundos, msg)
	local agora = Game.Timer()
	if _ultimaLinha[chave] and agora - _ultimaLinha[chave] < segundos then return end
	_ultimaLinha[chave] = agora
	Log(msg)
end
local _errosVistos = {}
local function LogErro(onde, err)
	local chave = tostring(onde) .. ":" .. tostring(err)
	if _errosVistos[chave] then return end
	_errosVistos[chave] = true
	Log("ERROR in " .. tostring(onde) .. ": " .. tostring(err))
end
local _vistos = {}
local function LogUmaVez(chave, msg)
	if _vistos[chave] then return end
	_vistos[chave] = true
	Log(msg)
end
local DIAG = true
local function Nao(chave, motivo)
	if not DIAG then return end
	LogComIntervalo("nao:" .. chave, 5, "NAO AGIU (" .. chave .. "): " .. motivo)
end
local function DistSq(a, b)
	if not (a and b) then return MathHuge end
	local dx, dy, dz = a.x - b.x, (a.y or 0) - (b.y or 0), a.z - b.z
	return dx * dx + dy * dy + dz * dz
end
local function Dist(a, b)
	local d = DistSq(a, b)
	return d == MathHuge and d or MathSqrt(d)
end
local _semDano = false
local function DanoDeAtaque(alvo)
	if not getdmg then
		if not _semDano then
			_semDano = true
			Log("NO DamageLib: finisher and farm reset are off -- both rules "
				.. "depend on knowing how much my shot takes")
		end
		return nil
	end
	local d = nil
	pcall(function() d = getdmg("AA", myHero, alvo) end)
	if type(d) ~= "number" or d <= 0 then return nil end
	return d
end
local function DanoDeHabilidade(slot, alvo)
	if not (getdmg and alvo) then return nil end
	local d = nil
	pcall(function() d = getdmg(slot, myHero, alvo) end)
	if type(d) ~= "number" or d <= 0 then return nil end
	return d
end
local function TemBuff(unit, nome)
	if not (unit and unit.valid and nome) then return false end
	local alvo = tostring(nome):lower()
	local tem = false
	pcall(function()
		for i = 0, (unit.buffCount or 0) do
			local b = unit:GetBuff(i)
			if b and b.count and b.count > 0 and b.name
				and tostring(b.name):lower() == alvo then
				tem = true
				return
			end
		end
	end)
	return tem
end
local function Pronto(slot)
	local pronto = false
	pcall(function()
		if Game.CanUseSpell(slot) == 0 then pronto = true return end
		local sd = myHero:GetSpellData(slot)
		if sd and (sd.level or 0) > 0 and (sd.currentCd or 0) <= 0 then pronto = true end
	end)
	return pronto
end
local function Valido(unit, alcance, de)
	if not (unit and unit.valid and unit.visible and not unit.dead) then return false end
	if unit.isImmortal then return false end
	if alcance then
		return DistSq(de or myHero.pos, unit.pos) <= alcance * alcance
	end
	return true
end
local function BuffsCom(unit)
	local mapa = {}
	if not (unit and unit.valid) then return mapa end
	pcall(function()
		for i = 0, (unit.buffCount or 0) do
			local b = unit:GetBuff(i)
			if b and b.count and b.count > 0 and b.name then
				mapa[tostring(b.name):lower()] = { n = b.count, expira = b.expireTime or 0 }
			end
		end
	end)
	return mapa
end
local function Inimigos(alcance)
	local lista = {}
	for i = 1, Game.HeroCount() do
		local h = Game.Hero(i)
		if h and h.isEnemy and Valido(h, alcance) then TableInsert(lista, h) end
	end
	return lista
end
_G.superCore = _G.superCore or {}
local Core = _G.superCore
Core.versao = MathMax(Core.versao or 0, 1)
local _viuEvade = false
function Core.Evade()
	local ev = _G.superEvade
	if ev and not _viuEvade then
		_viuEvade = true
		Log("first superEvade lookup -- API present, movement and danger checks defer to it")
	end
	return ev
end
function Core.Desviando()
	local sim = false
	pcall(function()
		local ev = Core.Evade()
		if ev and type(ev.Evading) == "function" then sim = ev.Evading() and true or false end
	end)
	return sim
end
function Core.PodeMover()
	return not Core.Desviando()
end
function Core.PodeLancar(prende)
	if not prende then return true end
	return not Core.Desviando()
end
local function Fugindo(unit)
	if not (unit and unit.valid) then return false end
	local sim = false
	pcall(function()
		local p = unit.pathing
		if not (p and p.hasMovePath and p.endPos) then return end
		sim = DistSq(p.endPos, myHero.pos) > DistSq(unit.pos, myHero.pos) + 100 * 100
	end)
	return sim
end
local function Recuando(unit)
	if not (unit and unit.valid) then return false, 0 end
	local sim, resta = false, 0
	pcall(function()
		local a = unit.activeSpell
		if a and a.valid and a.name and tostring(a.name):lower():find("recall", 1, true) then
			sim = true
			if a.castEndTime then
				local t = a.castEndTime - Game.Timer()
				if t > resta then resta = t end
			end
		end
		for i = 0, (unit.buffCount or 0) do
			local b = unit:GetBuff(i)
			if b and b.count and b.count > 0 and b.name
				and tostring(b.name):lower():find("recall", 1, true) then
				sim = true
				local t = (b.expireTime or 0) - Game.Timer()
				if t > resta then resta = t end
			end
		end
	end)
	return sim, resta
end
local CONGELA_POSICAO = {
	[5] = "Stun", [12] = "Snare", [25] = "Suppression",
	[30] = "Knockup", [35] = "Asleep",
}
function Core.ImobilizadoPor(unit)
	if not (unit and unit.valid) then return 0 end
	local resta = 0
	pcall(function()
		local a = unit.activeSpell
		if a and a.valid and a.isChanneling and a.castEndTime then
			local t = a.castEndTime - Game.Timer()
			if t > 0 then resta = t end
		end
		for i = 0, (unit.buffCount or 0) do
			local b = unit:GetBuff(i)
			if b and b.count and b.count > 0 and b.type and CONGELA_POSICAO[b.type] then
				local t = (b.expireTime or 0) - Game.Timer()
				if t > resta then resta = t end
			end
		end
	end)
	local recua, prazo = Recuando(unit)
	if recua and prazo > resta then resta = prazo end
	return resta
end
function Core.WindupRestante()
	local resta = 0
	pcall(function()
		local ad = myHero.attackData
		if not (ad and ad.endTime and ad.windDownTime) then return end
		local livre = ad.endTime - ad.windDownTime
		resta = MathMax(0, livre - Game.Timer())
	end)
	return resta
end
local function DeveEsperar()
	if myHero.dead then return true end
	local esperar = false
	pcall(function()
		if Game.IsChatOpen and Game.IsChatOpen() then esperar = true return end
		if Control.IsKeyDown(0x11) or Control.IsKeyDown(0x12) then esperar = true return end
		local a = myHero.activeSpell
		if a and a.valid then
			if a.isCharging then esperar = true return end
			local agora = Game.Timer()
			if a.startTime and a.castEndTime
				and agora >= a.startTime and agora <= a.castEndTime then esperar = true return end
		end
	end)
	return esperar
end
local function ViradoParaMim(unit)
	local sim = false
	pcall(function()
		local v = Vector(unit.pos - myHero.pos)
		local d = Vector(unit.dir)
		local ang = 180 - math.deg(math.acos((v * d) / (v:Len() * d:Len())))
		sim = math.abs(ang) < 90
	end)
	return sim
end
local function Combo()
	local ork = _G.SDK and _G.SDK.Orbwalker
	return (ork and ork.Modes and ork.Modes[0]) and true or false
end
local _torreQuando, _torreResposta = nil, false
local function SobTorreInimiga(pos)
	local agora = Game.Timer()
	if _torreQuando == agora then return _torreResposta end
	local sob = false
	pcall(function()
		for i = 1, Game.TurretCount() do
			local t = Game.Turret(i)
			if t and t.valid and not t.dead and t.isEnemy then
				local alcance = (t.boundingRadius or 88) + 775 + (myHero.boundingRadius or 65) / 2
				if DistSq(t.pos, pos) <= alcance * alcance then sob = true return end
			end
		end
	end)
	_torreQuando, _torreResposta = agora, sob
	return sob
end
local function Assedio()
	local ork = _G.SDK and _G.SDK.Orbwalker
	if not (ork and ork.Modes and ork.Modes[1]) then return false end
	if ADC.menu and ADC.menu.Torre and ADC.menu.Torre.assedio:Value()
		and SobTorreInimiga(myHero.pos) then
		LogComIntervalo("torre", 10, "ASSEDIO SUSPENSO: estou sob torre inimiga")
		return false
	end
	return true
end
local function Farmando()
	local ork = _G.SDK and _G.SDK.Orbwalker
	if not (ork and ork.Modes) then return false end
	return (ork.Modes[2] or ork.Modes[3] or ork.Modes[4]) and true or false
end
local _semPred = false
local function Prever(dados, alvo, confianca)
	if not (dados and alvo) then return nil end
	if not GGPrediction then
		if not _semPred then
			_semPred = true
			Log("NO GGPrediction: no skillshot will be cast -- "
				.. "only target-locked abilities work")
		end
		return nil
	end
	local pos = nil
	local ok, err = pcall(function()
		local p = GGPrediction:SpellPrediction(dados)
		p:GetPrediction(alvo, myHero)
		if p:CanHit(confianca or 2) then pos = p.CastPosition end
	end)
	if not ok then LogErro("Prever", err) end
	return pos
end
local function NomeDoSlot(tecla)
	if tecla == HK_Q then return "Q" end
	if tecla == HK_W then return "W" end
	if tecla == HK_E then return "E" end
	if tecla == HK_R then return "R" end
	return "?"
end
local function LancarPrevisto(tecla, dados, alvo, confianca)
	local preso = Core.ImobilizadoPor(alvo)
	if preso > 0 then
		local voo = (dados.Delay or 0)
		if dados.Speed and dados.Speed ~= MathHuge and dados.Speed > 0 then
			voo = voo + Dist(myHero.pos, alvo.pos) / dados.Speed
		end
		if preso >= voo then
			confianca = 0
			LogComIntervalo("imovel:" .. tostring(alvo.charName), 5, string.format(
				"ALVO PRESO: %s por %.2fs e o tiro leva %.2fs -- confianca dispensada",
				tostring(alvo.charName), preso, voo))
		end
	end
	local pos = Prever(dados, alvo, confianca)
	if not pos then
		LogComIntervalo("semprev:" .. tostring(tecla), 5, string.format(
			"NAO LANCOU %s: a previsao nao chegou a confianca %d contra %s a %d unidades",
			NomeDoSlot(tecla), confianca or 2, tostring(alvo.charName),
			MathFloor(Dist(myHero.pos, alvo.pos))))
		return false
	end
	Control.CastSpell(tecla, pos)
	return true
end
local function AlvoEm(alcance)
	local recuando, prazo = nil, 0
	local perto = MathHuge
	for _, e in ipairs(Inimigos(alcance)) do
		local recua, resta = Recuando(e)
		if recua then
			local d = Dist(myHero.pos, e.pos)
			if d < perto then recuando, perto, prazo = e, d, resta end
		end
	end
	if recuando then
		LogComIntervalo("recua:" .. tostring(recuando.charName), 3, string.format(
			"RECUANDO: %s a %d unidades, restam %.2fs de canal -- vale a viagem dele",
			tostring(recuando.charName), MathFloor(perto), prazo))
		return recuando
	end
	local alvo = nil
	pcall(function()
		local ork = _G.SDK and _G.SDK.Orbwalker
		if ork and ork.GetTarget then alvo = ork:GetTarget(alcance, nil, true) end
	end)
	if Valido(alvo, alcance) then return alvo end
	local perto, dperto = nil, MathHuge
	for _, e in ipairs(Inimigos(alcance)) do
		local d = Dist(myHero.pos, e.pos)
		if d < dperto then perto, dperto = e, d end
	end
	if perto then
		LogComIntervalo("alvolonge:" .. tostring(perto.charName), 5, string.format(
			"ALVO FORA DO ORBWALKER: %s a %d unidades, dentro do alcance %d -- "
			.. "o orbwalker nao devolveu ninguem",
			tostring(perto.charName), MathFloor(dperto), MathFloor(alcance)))
	end
	return perto
end
local function QuantosPerto(pos, raio)
	local n = 0
	for _, e in ipairs(Inimigos()) do
		if DistSq(e.pos, pos) <= raio * raio then n = n + 1 end
	end
	return n
end
local function TemManaPara(...)
	local slots = {...}
	local total = 0
	pcall(function()
		for i = 1, #slots do
			local sd = myHero:GetSpellData(slots[i])
			total = total + ((sd and sd.mana) or 0)
		end
	end)
	return (myHero.mana or 0) >= total
end
local ItensDeAtaque = {
	{ id = 3153, nome = "Botrk",   alvo = true,  vidaAlvo = 0 },
	{ id = 3144, nome = "Cutlass", alvo = true,  vidaAlvo = 0 },
	{ id = 3142, nome = "Youmuu",  alvo = false, vidaAlvo = 0 },
}
local ItemHotKey = {
	[ITEM_1] = HK_ITEM_1 or string.byte("1"),
	[ITEM_2] = HK_ITEM_2 or string.byte("2"),
	[ITEM_3] = HK_ITEM_3 or string.byte("3"),
	[ITEM_4] = HK_ITEM_4 or string.byte("4"),
	[ITEM_5] = HK_ITEM_5 or string.byte("5"),
	[ITEM_6] = HK_ITEM_6 or string.byte("6"),
	[ITEM_7] = HK_ITEM_7 or string.byte("7"),
}
local function SlotDoItem(id)
	local achado = nil
	pcall(function()
		for slot = ITEM_1, ITEM_7 do
			local d = myHero:GetItemData(slot)
			if d and d.itemID == id then achado = slot return end
		end
	end)
	if not achado then return nil end
	local pronto = false
	pcall(function()
		local sd = myHero:GetSpellData(achado)
		pronto = sd ~= nil and (sd.currentCd or 0) == 0
	end)
	if not pronto then return nil end
	return achado
end
local _ultimoItem = 0
local function UsarItens(menu)
	if not (menu.Itens and menu.Itens.usar:Value()) then return end
	if GetTickCount() - _ultimoItem < 500 then return end
	local alcance = (myHero.range or 550) + (myHero.boundingRadius or 65)
	local alvo = AlvoEm(alcance)
	if not alvo then return end
	local pct = (alvo.maxHealth and alvo.maxHealth > 0)
		and (alvo.health / alvo.maxHealth * 100) or 100
	if pct > menu.Itens.vida:Value() then return end
	for i = 1, #ItensDeAtaque do
		local item = ItensDeAtaque[i]
		local slot = SlotDoItem(item.id)
		if slot then
			local hk = ItemHotKey and ItemHotKey[slot]
			if hk then
				if item.alvo then
					local tela = alvo.pos:To2D()
					if tela and tela.onScreen then
						Control.SetCursorPos(MathFloor(tela.x), MathFloor(tela.y))
					end
				end
				Control.KeyDown(hk)
				Control.KeyUp(hk)
				_ultimoItem = GetTickCount()
				Log(string.format("ITEM: %s em %s (%d%% de vida)",
					item.nome, tostring(alvo.charName), MathFloor(pct)))
				return
			end
		end
	end
end
local Vayne = { charName = "Vayne" }
Vayne.Q = { slot = _Q, tecla = HK_Q, alcance = 300 }
Vayne.E = { slot = _E, tecla = HK_E, alcance = 550 }
Vayne.R = { slot = _R, tecla = HK_R }
Vayne.MARCA = "vaynesilvereddebuff"
function Vayne:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Tumble"})
		menu.Q:MenuElement({id = "usar", name = "Use in combo (attack reset)", value = true})
		menu.Q:MenuElement({id = "mirar", name = "Aim to keep the target in range", value = true})
		menu.Q:MenuElement({id = "fechar", name = "Roll to REACH a target out of range", value = true})
		menu.Q:MenuElement({id = "finalizar", name = "Reset to press a target that is dropping", value = true})
		menu.Q:MenuElement({id = "finalizarVida", name = "  target health below %", value = 35, min = 5, max = 70, step = 5})
		menu.Q:MenuElement({id = "farm", name = "Reset so the next minion is not lost", value = true})
		menu.Q:MenuElement({id = "farmMana", name = "  only with mana above %", value = 40, min = 0, max = 100, step = 5})
		menu.Q:MenuElement({id = "torre", name = "Do not roll under a turret", value = true})
		menu.Q:MenuElement({id = "multidao", name = "Do not roll next to N enemies", value = 3, min = 1, max = 5, step = 1})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Condemn"})
		menu.E:MenuElement({id = "usar", name = "Use only when it STUNS (wall)", value = true})
		menu.E:MenuElement({id = "empurrao", name = "Knockback distance", value = 425, min = 300, max = 500, step = 5})
		menu.E:MenuElement({id = "corpoacorpo", name = "E on melee that closes in", value = true})
		menu.E:MenuElement({id = "corpoacorpoDist", name = "  from", value = 300, min = 100, max = 500, step = 10})
		menu.E:MenuElement({id = "avanco", name = "E on whoever dashes at me", value = true})
		menu.E:MenuElement({id = "interromper", name = "E to interrupt a channel", value = true})
		menu.E:MenuElement({id = "interromperMin", name = "  from N seconds of channel", value = 0.75, min = 0.4, max = 2.0, step = 0.05})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Final Hour"})
		menu.R:MenuElement({id = "usar", name = "Use on its own", value = true})
		menu.R:MenuElement({id = "quantos", name = "With N enemies nearby", value = 3, min = 1, max = 5, step = 1})
		menu.R:MenuElement({id = "vida", name = "Or with my health below %", value = 45, min = 10, max = 90, step = 5})
		menu.R:MenuElement({id = "raio", name = "Counting radius", value = 900, min = 500, max = 1400, step = 50})
	menu:MenuElement({type = MENU, id = "Alvo", name = "Target"})
		menu.Alvo:MenuElement({id = "duasMarcas", name = "Force the one already at 2 marks", value = true})
	menu:MenuElement({type = MENU, id = "Draw", name = "Drawing"})
		menu.Draw:MenuElement({id = "Q", name = "Q range", value = true})
		menu.Draw:MenuElement({id = "E", name = "E range", value = true})
		menu.Draw:MenuElement({id = "marcas", name = "Marks on the target", value = true})
	pcall(function()
		for _, s in ipairs({ self.Q, self.E }) do
			local sd = myHero:GetSpellData(s.slot)
			if sd and sd.range and sd.range > 0 then s.alcance = sd.range end
		end
	end)
	self._ultimoQ, self._ultimoE, self._ultimoR = 0, 0, 0
end
function Vayne:Marcas(unit)
	local m = BuffsCom(unit)[self.MARCA]
	if not m then return 0, 0 end
	return m.n, MathMax(0, (m.expira or 0) - Game.Timer())
end
function Vayne:TempoAteMeuTiro(alvo)
	local t = 0.25
	pcall(function()
		local ad = myHero.attackData
		if ad and ad.windUpTime and ad.windUpTime > 0 then t = ad.windUpTime end
		local vel = (ad and ad.projectileSpeed and ad.projectileSpeed > 0) and ad.projectileSpeed or 2000
		t = t + Dist(myHero.pos, alvo.pos) / vel
	end)
	return t
end
function Vayne:AlvoPreferido()
	if not self.menu.Alvo.duasMarcas:Value() then return nil end
	local alcance = (myHero.range or 550) + (myHero.boundingRadius or 65)
	local melhor, melhorNota = nil, -MathHuge
	for _, e in ipairs(Inimigos(alcance)) do
		local marcas, restam = self:Marcas(e)
		if marcas >= 2 then
			local tiro = self:TempoAteMeuTiro(e)
			LogUmaVez("marca", string.format(
				"MARCA MEDIDA: %s tem %d marcas, restam %.2fs, meu tiro leva %.2fs",
				tostring(e.charName), marcas, restam, tiro))
			local cabe = (restam <= 0) or (restam >= tiro)
			if not cabe then
				LogComIntervalo("marcaexpira:" .. tostring(e.charName), 5, string.format(
					"MARCA EXPIRANDO: %s tem 2 marcas mas so por %.2fs, e meu tiro leva %.2fs",
					tostring(e.charName), restam, tiro))
			else
				local nota = (e.totalDamage or 0) + (e.bonusDamage or 0) + (e.ap or 0)
				local dano = DanoDeAtaque(e)
				if dano and e.health <= dano * 1.5 then nota = nota + 100000 end
				if nota > melhorNota then melhor, melhorNota = e, nota end
			end
		end
	end
	return melhor
end
function Vayne:DestinoDoTumble(alvo)
	local cursor = mousePos
	if not (alvo and self.menu.Q.mirar:Value()) then return cursor end
	local alcanceAtaque = (myHero.range or 550) + (myHero.boundingRadius or 65)
	local a, b = self:InterseccaoDeCirculos(myHero.pos, alvo.pos, self.Q.alcance, alcanceAtaque)
	if not (a and b) then return cursor end
	return DistSq(a, cursor) < DistSq(b, cursor) and a or b
end
function Vayne:InterseccaoDeCirculos(c1, c2, r1, r2)
	local d = Dist(c1, c2)
	if d > r1 + r2 or d < math.abs(r1 - r2) or d == 0 then return nil, nil end
	local a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
	local h2 = r1 * r1 - a * a
	if h2 < 0 then return nil, nil end
	local h = MathSqrt(h2)
	local mx = c1.x + a * (c2.x - c1.x) / d
	local mz = c1.z + a * (c2.z - c1.z) / d
	local rx = -(c2.z - c1.z) * (h / d)
	local rz = (c2.x - c1.x) * (h / d)
	return Vector(mx + rx, myHero.pos.y, mz + rz), Vector(mx - rx, myHero.pos.y, mz - rz)
end
function Vayne:TumbleSeguro(destino)
	if not destino then return false end
	if MapPosition:inWall(destino) then return false end
	if self.menu.Q.torre:Value() and self:SobTorre(destino) then return false end
	local limite = self.menu.Q.multidao:Value()
	local perto = 0
	for _, e in ipairs(Inimigos()) do
		if DistSq(e.pos, destino) <= 400 * 400 then perto = perto + 1 end
	end
	if perto >= limite then return false end
	local perigoso = false
	pcall(function()
		local ev = Core.Evade()
		if ev and ev.IsDangerous then perigoso = ev:IsDangerous(destino) and true or false end
	end)
	return not perigoso
end
function Vayne:SobTorre(pos)
	local sob = false
	pcall(function()
		for i = 1, Game.TurretCount() do
			local t = Game.Turret(i)
			if t and t.valid and not t.dead and t.isEnemy then
				local alcance = (t.boundingRadius or 88) + 775
				if DistSq(t.pos, pos) <= alcance * alcance then sob = true return end
			end
		end
	end)
	return sob
end
function Vayne:PosicaoPrevista(alvo)
	local pos = alvo.pos
	pcall(function()
		local t = 0.25 + Dist(myHero.pos, alvo.pos) / 1600
		local p = alvo.pathing
		if not (p and p.hasMovePath and p.endPos) then return end
		local vel = alvo.ms or 330
		local resta = Dist(alvo.pos, p.endPos)
		if resta < 1 or vel <= 0 then return end
		local anda = MathMin(vel * t, resta)
		pos = alvo.pos:Extended(p.endPos, anda)
	end)
	return pos
end
local function EhParede(pos)
	local parede = false
	pcall(function()
		if Game.isWall then parede = Game.isWall(pos) and true or false return end
		parede = MapPosition:inWall(pos) and true or false
	end)
	return parede
end
function Vayne:CondemnAtordoa(alvo)
	if not alvo then return false end
	local destino = self:PosicaoPrevista(alvo)
	local empurrao = self.menu.E.empurrao:Value() + (alvo.boundingRadius or 65)
	local achou = nil
	pcall(function()
		local fim = destino:Extended(myHero.pos, -empurrao)
		local total = Dist(destino, fim)
		if total < 1 then return end
		local d = 0
		while d <= total do
			local ponto = destino:Extended(fim, d)
			if EhParede(ponto) then achou = d return end
			d = d + 25
		end
	end)
	if not achou then return false end
	self._paredeA = achou
	self._paredeUsada = achou
	return true
end
function Vayne:UsarE(alvo, motivo)
	if not (Pronto(self.E.slot) and Valido(alvo, self.E.alcance)) then return false end
	if GetTickCount() - self._ultimoE < 500 then return false end
	Control.CastSpell(self.E.tecla, alvo)
	self._ultimoE = GetTickCount()
	self._ultimoMotivoE = motivo
	Log(string.format("CONDEMN: %s | %s | a %d unidades",
		tostring(alvo.charName), tostring(motivo), MathFloor(Dist(myHero.pos, alvo.pos))))
	self._medindoEmpurrao = {
		unit = alvo, de = alvo.pos, t = Game.Timer(), maior = 0,
		parede = self._paredeUsada,
	}
	self._paredeUsada = nil
	return true
end
function Vayne:ResetDeFarm(alvoAtacado)
	if not Core.PodeMover() then return false end
	if not (self.menu.Q.farm:Value() and Pronto(self.Q.slot)) then return false end
	if GetTickCount() - self._ultimoQ < 200 then return false end
	local mana = (myHero.mana / myHero.maxMana) * 100
	if mana < self.menu.Q.farmMana:Value() then return false end
	local alcance = (myHero.range or 550) + (myHero.boundingRadius or 65)
	local achou = false
	local ok, err = pcall(function()
		local om = _G.SDK and _G.SDK.ObjectManager
		if not om then return end
		for _, m in ipairs(om:GetEnemyMinions(alcance, true, true)) do
			if m ~= alvoAtacado and m.valid and not m.dead and m.health > 0 then
				local dano = DanoDeAtaque(m)
				if dano and m.health <= dano then achou = true return end
			end
		end
	end)
	if not ok then LogErro("ResetDeFarm", err) end
	if not achou then return false end
	local destino = mousePos
	if not self:TumbleSeguro(destino) then return false end
	Control.CastSpell(self.Q.tecla, destino)
	LogComIntervalo("qfarm", 3, "TUMBLE: reset de farm | outro minion ja morre de um tiro")
	self._ultimoQ = GetTickCount()
	return true
end
function Vayne:PosAtaque(alvoAtacado)
	LogComIntervalo("posataque", 10, "POS-ATAQUE: o gancho do orbwalker chegou")
	if DeveEsperar() then Nao("Q", "esperando (cast, chat ou modificador)") return end
	if not Core.PodeMover() then Nao("Q", "o evade esta desviando e o Tumble move") return end
	if Farmando() and self:ResetDeFarm(alvoAtacado) then return end
	if not (Combo() or Assedio()) then Nao("Q", "fora de combo e de assedio") return end
	if not self.menu.Q.usar:Value() then Nao("Q", "desligado no menu") return end
	if not Pronto(self.Q.slot) then Nao("Q", "Tumble nao esta pronto") return end
	if GetTickCount() - self._ultimoQ < 200 then Nao("Q", "menos de 200ms do ultimo") return end
	local alvo = self._alvoAtual
	local destino = self:DestinoDoTumble(alvo)
	if not self:TumbleSeguro(destino) then Nao("Q", "destino recusado pelas travas") return end
	Control.CastSpell(self.Q.tecla, destino)
	LogComIntervalo("qreset", 3, string.format(
		"TUMBLE: reset de ataque%s | %d unidades",
		alvo and (" mantendo " .. tostring(alvo.charName)) or "",
		MathFloor(MathMin(Dist(myHero.pos, destino), self.Q.alcance))))
	self._ultimoQ = GetTickCount()
end
function Vayne:FecharDistancia()
	if not Core.PodeMover() then return false end
	if not (self.menu.Q.fechar:Value() and Pronto(self.Q.slot)) then return false end
	if GetTickCount() - self._ultimoQ < 200 then return false end
	local alcanceAtaque = (myHero.range or 550) + (myHero.boundingRadius or 65)
	local ork = _G.SDK and _G.SDK.Orbwalker
	local alvo = self._alvoAtual
	if not alvo and ork and ork.GetTarget then
		alvo = ork:GetTarget(alcanceAtaque + self.Q.alcance, nil, true)
	end
	if not Valido(alvo) then return false end
	local d = Dist(myHero.pos, alvo.pos)
	if d <= alcanceAtaque then return false end
	if d > alcanceAtaque + self.Q.alcance then return false end
	local destino = myHero.pos:Extended(alvo.pos, self.Q.alcance)
	if not self:TumbleSeguro(destino) then return false end
	Control.CastSpell(self.Q.tecla, destino)
	Log(string.format("TUMBLE: fechando distancia para %s | %d -> %d unidades",
		tostring(alvo.charName), MathFloor(d), MathFloor(d - self.Q.alcance)))
	self._ultimoQ = GetTickCount()
	return true
end
function Vayne:MedirEmpurrao()
	local m = self._medindoEmpurrao
	if not m then return end
	local agora = Game.Timer()
	if agora - m.t > 1.2 then
		self._medindoEmpurrao = nil
		if m.maior > 50 then
			if m.parede then
				LogUmaVez("paredeconfere", string.format(
					"PAREDE CONFERIDA: %s andou %d unidades e a parede estava a %d -- "
					.. "diferenca de %d (corpo do alvo mais a amostragem)",
					tostring(m.unit.charName), MathFloor(m.maior), MathFloor(m.parede),
					MathFloor(MathAbs(m.parede - m.maior))))
			else
				LogUmaVez("empurrao", string.format(
					"EMPURRAO LIVRE MEDIDO: %s andou %d unidades sem parede no caminho "
					.. "(a tabela diz %d) -- este e o numero que corrige o slider",
					tostring(m.unit.charName), MathFloor(m.maior),
					self.menu.E.empurrao:Value()))
			end
		end
		return
	end
	pcall(function()
		if not (m.unit and m.unit.valid and not m.unit.dead) then return end
		local d = Dist(m.de, m.unit.pos)
		if d > m.maior then m.maior = d end
	end)
end
function Vayne:Finalizar()
	if not Core.PodeMover() then return false end
	if not self.menu.Q.finalizar:Value() then return false end
	if not Pronto(self.Q.slot) then return false end
	if GetTickCount() - self._ultimoQ < 200 then return false end
	local ork = _G.SDK and _G.SDK.Orbwalker
	if not ork then return false end
	local podeAtacar = true
	pcall(function() podeAtacar = ork.CanAttack and ork:CanAttack() and true or false end)
	if podeAtacar then return false end
	local alcance = (myHero.range or 550) + (myHero.boundingRadius or 65)
	local limiar = self.menu.Q.finalizarVida:Value()
	local vitima, razao, pior = nil, nil, MathHuge
	for _, e in ipairs(Inimigos(alcance)) do
		local dano = DanoDeAtaque(e)
		local pct = (e.maxHealth and e.maxHealth > 0) and (e.health / e.maxHealth * 100) or 100
		local morre = dano and e.health <= dano
		local caindo = pct <= limiar
		if (morre or caindo) and pct < pior then
			vitima, pior = e, pct
			razao = morre and "morre de um tiro" or string.format("vida em %d%%", MathFloor(pct))
		end
	end
	if not vitima then return false end
	local destino = self:DestinoDoTumble(vitima)
	if not self:TumbleSeguro(destino) then
		Nao("finalizar", "o abate estava la mas o destino do salto foi recusado")
		return false
	end
	Control.CastSpell(self.Q.tecla, destino)
	self._ultimoQ = GetTickCount()
	Log(string.format("TUMBLE PARA PRESSIONAR: %s (%s) | %d de vida, meu tiro tira %d",
		tostring(vitima.charName), tostring(razao), MathFloor(vitima.health),
		MathFloor(DanoDeAtaque(vitima) or 0)))
	return true
end
function Vayne:Tick()
	self:MedirEmpurrao()
	if DeveEsperar() then return end
	local ork = _G.SDK and _G.SDK.Orbwalker
	local preferido = self:AlvoPreferido()
	if ork then
		if Combo() or Assedio() then
			local id = preferido and tostring(preferido.networkID) or nil
			if id and id ~= self._ultimoForcado then
				Log(string.format("ALVO FORCADO: %s com 2 marcas", tostring(preferido.charName)))
			end
			self._ultimoForcado = id
			ork.ForceTarget = preferido
			self._alvoAtual = preferido or (ork.GetTarget and ork:GetTarget(
				(myHero.range or 550) + (myHero.boundingRadius or 65), nil, true)) or nil
		else
			ork.ForceTarget = nil
			self._alvoAtual = nil
			self._ultimoForcado = nil
		end
	end
	if Combo() then
		self:Finalizar()
		self:UsarR()
		self:FecharDistancia()
		if self.menu.E.usar:Value() then
			if not Pronto(self.E.slot) then
				Nao("E", "Condemn nao esta pronto")
			else
				local melhor, marcas = nil, -1
				local candidatos = 0
				for _, e in ipairs(Inimigos(self.E.alcance)) do
					candidatos = candidatos + 1
					if self:CondemnAtordoa(e) then
						local n = self:Marcas(e)
						if n > marcas then melhor, marcas = e, n end
					end
				end
				if melhor then
					self:UsarE(melhor, string.format("atordoa na parede a %d unidades (%d marcas)",
						MathFloor(self._paredeA or -1), marcas))
				elseif candidatos == 0 then
				else
					Nao("E", string.format("nenhum dos %d inimigos tem parede atras", candidatos))
				end
			end
		end
	end
	if not self:Interromper() then
		self:Defensivo()
	end
end
function Vayne:Interromper()
	if not (self.menu.E.interromper:Value() and Pronto(self.E.slot)) then return false end
	local alvo, dura = nil, 0
	local minimo = self.menu.E.interromperMin:Value()
	for _, e in ipairs(Inimigos(self.E.alcance)) do
		pcall(function()
			local a = e.activeSpell
			if not (a and a.valid and a.startTime and a.castEndTime) then return end
			local total = a.castEndTime - a.startTime
			if total < minimo then return end
			if a.castEndTime - Game.Timer() < 0.2 then return end
			if total > dura then alvo, dura = e, total end
		end)
	end
	if not alvo then return false end
	return self:UsarE(alvo, string.format("interrompendo canal de %.2fs", dura))
end
function Vayne:Defensivo()
	if not Pronto(self.E.slot) then return end
	local candidatos = {}
	for _, e in ipairs(Inimigos(self.E.alcance)) do
		local motivo = nil
		if self.menu.E.corpoacorpo:Value()
			and (e.range or 500) < 400
			and DistSq(myHero.pos, e.pos) <= self.menu.E.corpoacorpoDist:Value() ^ 2 then
			motivo = "corpo a corpo encostou"
		end
		if not motivo and self.menu.E.avanco:Value() and self:AvancaParaMim(e) then
			motivo = "avanco na minha direcao"
		end
		if motivo and ViradoParaMim(e) then
			TableInsert(candidatos, { unit = e, motivo = motivo,
				nota = (e.health or 0) + (e.totalDamage or 0) * 2 + (e.attackSpeed or 1) * 100 })
		end
	end
	if #candidatos == 0 then return end
	table.sort(candidatos, function(a, b) return a.nota > b.nota end)
	self:UsarE(candidatos[1].unit, candidatos[1].motivo)
end
function Vayne:AvancaParaMim(unit)
	local p = unit.pathing
	if not (p and p.isDashing and p.hasMovePath and (p.dashSpeed or 0) > 0 and p.endPos) then
		return false
	end
	if DistSq(p.endPos, myHero.pos) >= DistSq(unit.pos, myHero.pos) then return false end
	return DistSq(p.endPos, myHero.pos) <= 400 * 400
end
function Vayne:UsarR()
	if not self.menu.R.usar:Value() then return end
	if not Pronto(self.R.slot) then Nao("R", "Final Hour nao esta pronto") return end
	if GetTickCount() - self._ultimoR < 1000 then return end
	local perto = #Inimigos(self.menu.R.raio:Value())
	local vida = (myHero.health / myHero.maxHealth) * 100
	if not (perto >= self.menu.R.quantos:Value() or (perto > 0 and vida <= self.menu.R.vida:Value())) then
		Nao("R", string.format("%d inimigos (pede %d) e vida %d%% (pede <=%d)",
			perto, self.menu.R.quantos:Value(), MathFloor(vida), self.menu.R.vida:Value()))
	end
	if perto >= self.menu.R.quantos:Value() or (perto > 0 and vida <= self.menu.R.vida:Value()) then
		Control.CastSpell(self.R.tecla)
		self._ultimoR = GetTickCount()
		Log(string.format("FINAL HOUR: %d inimigos em %d unidades, minha vida %d%%",
			perto, self.menu.R.raio:Value(), MathFloor(vida)))
	end
end
function Vayne:Draw()
	if myHero.dead then return end
	if self.menu.Draw.Q:Value() and Pronto(self.Q.slot) then
		Draw.Circle(myHero.pos, self.Q.alcance, 1, Draw.Color(80, 255, 255, 255))
	end
	if self.menu.Draw.E:Value() and Pronto(self.E.slot) then
		Draw.Circle(myHero.pos, self.E.alcance, 1, Draw.Color(80, 255, 255, 255))
	end
	if self.menu.Draw.marcas:Value() then
		for _, e in ipairs(Inimigos(1500)) do
			local n = self:Marcas(e)
			if n > 0 then
				local p = e.pos:To2D()
				if p and p.onScreen then
					local cor = (n >= 2) and Draw.Color(255, 255, 80, 80) or Draw.Color(255, 120, 220, 120)
					Draw.Text(tostring(n) .. "/3", 18, p.x - 10, p.y - 40, cor)
				end
			end
		end
	end
end
local Ashe = { charName = "Ashe" }
Ashe.W = { slot = _W, tecla = HK_W,
	Type = 0, Delay = 0.25, Radius = 20, Range = 1200, Speed = 2000, Collision = true }
Ashe.R = { slot = _R, tecla = HK_R,
	Type = 0, Delay = 0.25, Radius = 130, Range = 12500, Speed = 1600, Collision = false }
function Ashe:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "W", name = "W -- Volley"})
		menu.W:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.W:MenuElement({id = "assedio", name = "Use to harass", value = true})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Enchanted Crystal Arrow"})
		menu.R:MenuElement({id = "usar", name = "Use on its own in a group", value = true})
		menu.R:MenuElement({id = "quantos", name = "With N enemies together", value = 3, min = 1, max = 5, step = 1})
		menu.R:MenuElement({id = "raio", name = "  measured within a radius of", value = 250, min = 150, max = 500, step = 25})
		menu.R:MenuElement({id = "abate", name = "Use to finish at range", value = true})
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Ranger Focus"})
		menu.Q:MenuElement({id = "usar", name = "Use in combo with a target in range", value = true})
end
function Ashe:Tick()
	if DeveEsperar() then return end
	if Combo() then
		self:Ultimate()
		if self.menu.W.combo:Value() and Pronto(_W) then
			local alvo = AlvoEm(self.W.Range)
			if alvo and LancarPrevisto(self.W.tecla, self.W, alvo, 2) then
				LogComIntervalo("ashew", 3, "VOLLEY: em " .. tostring(alvo.charName))
			end
		end
		if self.menu.Q.usar:Value() and Pronto(_Q) then
			local alcance = (myHero.range or 600) + (myHero.boundingRadius or 65)
			if AlvoEm(alcance) then Control.CastSpell(HK_Q) end
		end
	elseif Assedio() and self.menu.W.assedio:Value() and Pronto(_W) then
		local alvo = AlvoEm(self.W.Range)
		if alvo then LancarPrevisto(self.W.tecla, self.W, alvo, 2) end
	end
end
function Ashe:Ultimate(soAbate)
	if not Pronto(_R) then return end
	if GetTickCount() - (self._ultimoR or 0) < 1000 then return end
	if self.menu.R.usar:Value() and not soAbate then
		local alvo = AlvoEm(2000)
		if alvo then
			local juntos = QuantosPerto(alvo.pos, self.menu.R.raio:Value())
			if juntos >= self.menu.R.quantos:Value()
				and LancarPrevisto(self.R.tecla, self.R, alvo, 3) then
				self._ultimoR = GetTickCount()
				Log(string.format("ARROW: %d inimigos juntos em volta de %s",
					juntos, tostring(alvo.charName)))
				return
			end
		end
	end
	if self.menu.R.abate:Value() then
		for _, e in ipairs(Inimigos(self.R.Range)) do
			local dano = DanoDeHabilidade("R", e)
			if dano and e.health <= dano
				and LancarPrevisto(self.R.tecla, self.R, e, 3) then
				self._ultimoR = GetTickCount()
				Log(string.format("ARROW PARA MATAR: %s com %d de vida, o R tira %d",
					tostring(e.charName), MathFloor(e.health), MathFloor(dano)))
				return
			end
		end
	end
end
local Caitlyn = { charName = "Caitlyn" }
Caitlyn.Q = { slot = _Q, tecla = HK_Q,
	Type = 0, Delay = 0.625, Radius = 60, Range = 1240, Speed = 2200, Collision = false }
Caitlyn.E = { slot = _E, tecla = HK_E,
	Type = 0, Delay = 0.15, Radius = 70, Range = 750, Speed = 1600, Collision = true }
Caitlyn.R = { slot = _R, tecla = HK_R, Range = 3500 }
function Caitlyn:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Piltover Peacemaker"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "minimo", name = "  only with the target beyond", value = 500, min = 0, max = 900, step = 50})
	menu:MenuElement({type = MENU, id = "E", name = "E -- 90 Caliber Net"})
		menu.E:MenuElement({id = "combo", name = "Use in combo (backs off and marks)", value = true})
		menu.E:MenuElement({id = "alcance", name = "  only with the target within", value = 500, min = 200, max = 750, step = 25})
		menu.E:MenuElement({id = "fuga", name = "Use on melee that closes in", value = true})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Ace in the Hole"})
		menu.R:MenuElement({id = "abate", name = "Use to finish an isolated target", value = true})
end
function Caitlyn:Tick()
	if DeveEsperar() then return end
	self:Defensivo()
	if not Combo() then return end
	if self.menu.E.combo:Value() and Pronto(_E) then
		local alvo = AlvoEm(self.menu.E.alcance:Value())
		if alvo then
			local atras = myHero.pos:Extended(alvo.pos, -400)
			if QuantosPerto(atras, 700) < 2 and TemManaPara(_E, _Q)
				and LancarPrevisto(self.E.tecla, self.E, alvo, 2) then
				Log("NET: backing off and marking " .. tostring(alvo.charName))
			end
		end
	end
	if self.menu.Q.combo:Value() and Pronto(_Q) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo and Dist(myHero.pos, alvo.pos) > self.menu.Q.minimo:Value()
			and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("caitq", 3, "PEACEMAKER: em " .. tostring(alvo.charName))
		end
	end
	self:Ultimate()
end
function Caitlyn:Ultimate()
	if not Core.PodeLancar(true) then return end
	if not (self.menu.R.abate:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 2000 then return end
	for _, e in ipairs(Inimigos(self.R.Range)) do
		local dano = DanoDeHabilidade("R", e)
		if dano and e.health <= dano and QuantosPerto(e.pos, 500) == 1 then
			Control.CastSpell(self.R.tecla, e)
			self._ultimoR = GetTickCount()
			Log(string.format("ACE IN THE HOLE: %s sozinho, com %d de vida e o R tira %d",
				tostring(e.charName), MathFloor(e.health), MathFloor(dano)))
			return
		end
	end
end
function Caitlyn:Defensivo()
	if not (self.menu.E.fuga:Value() and Pronto(_E)) then return end
	if GetTickCount() - (self._ultimoE or 0) < 500 then return end
	for _, e in ipairs(Inimigos(400)) do
		if (e.range or 500) < 400 and ViradoParaMim(e)
			and LancarPrevisto(self.E.tecla, self.E, e, 2) then
			self._ultimoE = GetTickCount()
			Log("NET: escaping " .. tostring(e.charName) .. " who closed in")
			return
		end
	end
end
local Jinx = { charName = "Jinx" }
Jinx.Q = { slot = _Q, tecla = HK_Q, Range = 525 }
Jinx.W = { slot = _W, tecla = HK_W,
	Type = 0, Delay = 0.6, Radius = 60, Range = 1450, Speed = 3300, Collision = true }
Jinx.E = { slot = _E, tecla = HK_E,
	Type = 1, Delay = 0.75, Radius = 120, Range = 925, Speed = MathHuge, Collision = false }
Jinx.R = { slot = _R, tecla = HK_R,
	Type = 0, Delay = 0.6, Radius = 140, Range = 25000, Speed = 1700, Collision = false }
Jinx.BONUS_Q = { 100, 125, 150, 175, 200 }
function Jinx:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Switcheroo"})
		menu.Q:MenuElement({id = "usar", name = "Switch weapon automatically", value = true})
		menu.Q:MenuElement({id = "juntos", name = "Rocket with 2+ targets clumped", value = true})
		menu.Q:MenuElement({id = "raio", name = "  clumped within", value = 150, min = 100, max = 600, step = 25})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Zap"})
		menu.W:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.W:MenuElement({id = "minimo", name = "  only with the target beyond", value = 0, min = 0, max = 1400, step = 50})
		menu.W:MenuElement({id = "assedio", name = "Use to harass", value = false})
		menu.W:MenuElement({id = "abate", name = "Use to finish at range", value = true})
		menu.W:MenuElement({id = "fog", name = "Use on whoever vanishes into brush or fog", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Flame Chompers"})
		menu.E:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.E:MenuElement({id = "fuga", name = "Use on whoever dashes at me", value = true})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Super Mega Death Rocket"})
		menu.R:MenuElement({id = "abate", name = "Use to finish at range", value = true})
		menu.R:MenuElement({id = "alcance", name = "  up to", value = 25000, min = 1000, max = 25000, step = 500})
		menu.R:MenuElement({id = "area", name = "  blast radius", value = 250, min = 100, max = 500, step = 25})
		menu.R:MenuElement({id = "fog", name = "Finish a target lost in the fog", value = true})
		menu.R:MenuElement({id = "fogtempo", name = "  until gone for", value = 2000, min = 500, max = 4000, step = 250})
end
function Jinx:AlcanceFoguete(alvo)
	local nivel = 1
	pcall(function() nivel = MathMax(1, myHero:GetSpellData(_Q).level or 1) end)
	return self.Q.Range + (self.BONUS_Q[nivel] or 100)
		+ (myHero.boundingRadius or 65) + ((alvo and alvo.boundingRadius) or 65)
end
function Jinx:AlcanceBase(alvo)
	return self.Q.Range + (myHero.boundingRadius or 65) + ((alvo and alvo.boundingRadius) or 65)
end
function Jinx:Tick()
	if DeveEsperar() then return end
	self:Defensivo()
	if not (Combo() or Assedio()) then
		if self.menu.Q.usar:Value() and Pronto(_Q)
			and TemBuff(myHero, "jinxq") and #Inimigos(1500) == 0 then
			Control.CastSpell(HK_Q)
		end
		return
	end
	if Combo() then self:TrocaDeArma() end
	if Pronto(_W) then
		local usar = (Combo() and self.menu.W.combo:Value())
			or (Assedio() and self.menu.W.assedio:Value())
		if usar then
			local alvo = AlvoEm(self.W.Range)
			local confianca = 2
			if alvo and Fugindo(alvo) then confianca = 1 end
			if alvo and Dist(myHero.pos, alvo.pos) > self.menu.W.minimo:Value()
				and LancarPrevisto(self.W.tecla, self.W, alvo, confianca) then
				LogComIntervalo("jinxw", 3, string.format("ZAP: em %s a %d unidades (alcance %d)",
					tostring(alvo.charName), MathFloor(Dist(myHero.pos, alvo.pos)),
					MathFloor(self.W.Range)))
			end
		end
	end
	if Combo() and self.menu.E.combo:Value() and Pronto(_E) then
		local alvo = AlvoEm(self.E.Range)
		if alvo and LancarPrevisto(self.E.tecla, self.E, alvo, 3) then
			LogComIntervalo("jinxe", 3, "CHOMPERS: em " .. tostring(alvo.charName))
		end
	end
	if Combo() then self:Ultimate() end
end
function Jinx:TrocaDeArma()
	if not (self.menu.Q.usar:Value() and Pronto(_Q)) then return end
	local alvo = AlvoEm(1200)
	if not alvo then return end
	local d = Dist(myHero.pos, alvo.pos)
	local comFoguete = TemBuff(myHero, "jinxq")
	local juntos = 0
	if self.menu.Q.juntos:Value() then
		juntos = QuantosPerto(alvo.pos, self.menu.Q.raio:Value())
	end
	if juntos >= 2 and not comFoguete and d <= self:AlcanceFoguete(alvo) then
		Control.CastSpell(HK_Q)
		LogComIntervalo("jinxtroca", 3, string.format(
			"FOGUETE: %d alvos dentro de %d em volta de %s -- o estilhaco pega os dois",
			juntos, MathFloor(self.menu.Q.raio:Value()), tostring(alvo.charName)))
	elseif d > self:AlcanceBase(alvo) and d <= self:AlcanceFoguete(alvo) and not comFoguete then
		Control.CastSpell(HK_Q)
		LogComIntervalo("jinxtroca", 3, string.format(
			"FOGUETE: %s a %d, fora da minigun (%d) e dentro do foguete (%d)",
			tostring(alvo.charName), MathFloor(d),
			MathFloor(self:AlcanceBase(alvo)), MathFloor(self:AlcanceFoguete(alvo))))
	elseif d < self:AlcanceBase(alvo) and comFoguete and juntos < 2 then
		Control.CastSpell(HK_Q)
		LogComIntervalo("jinxtroca", 3, "MINIGUN: alvo entrou no alcance curto")
	end
end
function Jinx:FoguetePraRecall(e, vida, dano, d)
	local recua, resta = Recuando(e)
	if not (recua and resta and resta > 0) then return false end
	local voo = (self.R.Delay or 0.6) + d / (self.R.Speed or 1700)
	if voo >= resta then
		LogComIntervalo("recalltarde:" .. tostring(e.charName), 3, string.format(
			"RECALL FORA DE ALCANCE NO TEMPO: %s some em %.2fs e o foguete leva %.2fs "
			.. "para chegar a %d unidades", tostring(e.charName), resta, voo, MathFloor(d)))
		return false
	end
	if self:BloqueadoPorOutro(e, vida) then return false end
	if not LancarPrevisto(self.R.tecla, self.R, e, 2) then return false end
	self._ultimoR = GetTickCount()
	Log(string.format(
		"ROCKET NO RECALL: %s com %d de vida efetiva a %d unidades, some em %.2fs | "
		.. "o foguete chega em %.2fs e tira %d",
		tostring(e.charName), MathFloor(vida), MathFloor(d), resta, voo, MathFloor(dano)))
	return true
end
function Jinx:ZapMata(e, vida)
	local dw = DanoDeHabilidade("W", e)
	return dw ~= nil and vida <= dw
end
local function VidaEfetiva(e)
	return (e.health or 0) + (e.shieldAD or 0) + (e.shieldAP or 0)
end
function Jinx:BloqueadoPorOutro(alvo, vida)
	local bloq = self:QuemBloqueia(alvo.pos, alvo)
	if not bloq then return false end
	local separados = Dist(bloq.pos, alvo.pos)
	local raioR = self.menu.R.area:Value()
	if separados <= raioR then
		LogComIntervalo("rareia:" .. tostring(alvo.charName), 5, string.format(
			"ROCKET MESMO ASSIM: %s esta atras de %s, mas a %d unidades dele -- "
			.. "a explosao (%d) pega os dois",
			tostring(alvo.charName), tostring(bloq.charName),
			MathFloor(separados), MathFloor(raioR)))
		return false
	end
	LogComIntervalo("rabloq:" .. tostring(alvo.charName), 5, string.format(
		"ROCKET BLOQUEADO: %s morreria, mas %s esta na frente e a %d unidades dele "
		.. "-- o foguete para nele e a explosao (%d) nao alcanca",
		tostring(alvo.charName), tostring(bloq.charName),
		MathFloor(separados), MathFloor(raioR)))
	return true
end
function Jinx:QuemBloqueia(destino, alvo)
	local bloqueador = nil
	pcall(function()
		local ax, ay = myHero.pos.x, myHero.pos.z
		local bx, by = destino.x, destino.z
		local dx, dy = bx - ax, by - ay
		local comp2 = dx * dx + dy * dy
		if comp2 <= 0 then return end
		local alvoD = Dist(myHero.pos, destino)
		for _, e in ipairs(Inimigos()) do
			if not (alvo and e.networkID == alvo.networkID) then
				local t = ((e.pos.x - ax) * dx + (e.pos.z - ay) * dy) / comp2
				if t > 0 and t < 1 then
					local px, py = ax + dx * t, ay + dy * t
					local lateral = MathSqrt((e.pos.x - px) ^ 2 + (e.pos.z - py) ^ 2)
					if lateral <= (e.boundingRadius or 65) + (self.R.Radius or 140)
						and Dist(myHero.pos, e.pos) < alvoD then
						bloqueador = e
						return
					end
				end
			end
		end
	end)
	return bloqueador
end
function Jinx:LembrarInimigos()
	self._visto = self._visto or {}
	for _, e in ipairs(Inimigos()) do
		local destino = nil
		pcall(function()
			local p = e.pathing
			if p and p.hasMovePath and p.endPos then destino = e.pathing.endPos end
		end)
		self._visto[tostring(e.networkID)] = {
			pos = e.pos, destino = destino, t = GetTickCount(),
			vida = VidaEfetiva(e), ms = e.ms or 335, nome = tostring(e.charName),
			unidade = e,
		}
	end
end
function Jinx:OndeDeveEstar(reg)
	if not (reg and reg.pos and reg.destino) then return nil end
	local decorrido = (GetTickCount() - reg.t) / 1000
	if decorrido <= 0 then return reg.pos end
	local andou = (reg.ms or 335) * decorrido
	local total = Dist(reg.pos, reg.destino)
	if total <= 0 then return reg.pos end
	if andou >= total then return reg.destino end
	local t = andou / total
	return Vector(
		reg.pos.x + (reg.destino.x - reg.pos.x) * t,
		reg.pos.y + (reg.destino.y - reg.pos.y) * t,
		reg.pos.z + (reg.destino.z - reg.pos.z) * t)
end
function Jinx:ZapNaEscuridao()
	if not (self.menu.W.fog:Value() and Pronto(_W)) then return false end
	if GetTickCount() - (self._ultimoW or 0) < 1000 then return false end
	if not self._visto then return false end
	local limite = self.menu.R.fogtempo:Value()
	for _, reg in pairs(self._visto) do
		local idade = GetTickCount() - reg.t
		local u = reg.unidade
		local sumiu = u and u.valid and not u.dead and not u.visible
		if sumiu and idade > 150 and idade <= limite then
			local ponto = self:OndeDeveEstar(reg)
			if ponto then
				local d = Dist(myHero.pos, ponto)
				if d <= self.W.Range then
					Control.CastSpell(self.W.tecla, ponto)
					self._ultimoW = GetTickCount()
					Log(string.format(
						"ZAP NA ESCURIDAO: %s sumiu ha %dms | mirando o destino do ultimo "
						.. "clique, a %d unidades", tostring(reg.nome),
						MathFloor(idade), MathFloor(d)))
					return true
				end
			end
		end
	end
	return false
end
function Jinx:AbaterNaNeblina()
	if not (self.menu.R.fog:Value() and Pronto(_R)) then return false end
	if GetTickCount() - (self._ultimoR or 0) < 1000 then return false end
	if not self._visto then return false end
	local limite = self.menu.R.fogtempo:Value()
	for _, reg in pairs(self._visto) do
		local idade = GetTickCount() - reg.t
		local u = reg.unidade
		local sumiu = u and u.valid and not u.dead and not u.visible
		if sumiu and idade > 150 and idade <= limite then
			local ponto = self:OndeDeveEstar(reg)
			local dano = u and DanoDeHabilidade("R", u) or nil
			if ponto and dano and reg.vida * 1.15 <= dano then
				local d = Dist(myHero.pos, ponto)
				local bloq = self:QuemBloqueia(ponto, u)
				if bloq and Dist(bloq.pos, ponto) > self.menu.R.area:Value() then
					LogComIntervalo("fogbloq:" .. tostring(reg.nome), 5, string.format(
						"ROCKET NA NEBLINA BLOQUEADO: %s estaria a %d, mas %s esta na frente",
						tostring(reg.nome), MathFloor(Dist(myHero.pos, ponto)),
						tostring(bloq.charName)))
				elseif d <= self.menu.R.alcance:Value() and d > self.W.Range then
					Control.CastSpell(self.R.tecla, ponto)
					self._ultimoR = GetTickCount()
					Log(string.format(
						"ROCKET NA NEBLINA: %s sumiu ha %dms com %d de vida | mirando o "
						.. "destino do ultimo clique, a %d unidades | o R tira %d",
						tostring(reg.nome), MathFloor(idade), MathFloor(reg.vida),
						MathFloor(d), MathFloor(dano)))
					return true
				end
			end
		end
	end
	return false
end
function Jinx:FolgaDePasso(e)
	if Fugindo(e) then return 0 end
	return (myHero.ms or 330) * (self.R.Delay or 0.6)
end
function Jinx:ZapParaMatar()
	if not (self.menu.W.abate:Value() and Pronto(_W)) then return false end
	if GetTickCount() - (self._ultimoW or 0) < 1000 then return false end
	for _, e in ipairs(Inimigos(self.W.Range)) do
		local dano = DanoDeHabilidade("W", e)
		local vida = VidaEfetiva(e)
		if not dano then
			LogComIntervalo("zapsemdano:" .. tostring(e.charName), 5, string.format(
				"ZAP NAO ABATE: %s -- o DamageLib nao devolveu dano para o W",
				tostring(e.charName)))
		elseif vida > dano then
			LogComIntervalo("zapfraco:" .. tostring(e.charName), 5, string.format(
				"ZAP NAO ABATE: %s tem %d de vida efetiva e o W tira %d -- falta %d",
				tostring(e.charName), MathFloor(vida), MathFloor(dano),
				MathFloor(vida - dano)))
		end
		if dano and vida <= dano and LancarPrevisto(self.W.tecla, self.W, e, 2) then
			self._ultimoW = GetTickCount()
			self._zapEm = { alvo = tostring(e.networkID), t = GetTickCount(),
				chega = 1000 * (self.W.Delay + Dist(myHero.pos, e.pos) / self.W.Speed) }
			Log(string.format(
				"ZAP PARA MATAR: %s com %d de vida efetiva a %d unidades | o W tira %d",
				tostring(e.charName), MathFloor(vida),
				MathFloor(Dist(myHero.pos, e.pos)), MathFloor(dano)))
			return true
		end
	end
	return false
end
function Jinx:ZapACaminho(e)
	local z = self._zapEm
	if not (z and e and tostring(e.networkID) == z.alvo) then return false end
	return (GetTickCount() - z.t) < (z.chega + 150)
end
function Jinx:Ultimate()
	self:LembrarInimigos()
	if self:ZapParaMatar() then return end
	if self:AbaterNaNeblina() then return end
	if self:ZapNaEscuridao() then return end
	if not (self.menu.R.abate:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 1000 then return end
	for _, e in ipairs(Inimigos(self.menu.R.alcance:Value())) do
		local dano = DanoDeHabilidade("R", e)
		local vida = VidaEfetiva(e)
		if dano and vida <= dano then
			local d = Dist(myHero.pos, e.pos)
			if self:FoguetePraRecall(e, vida, dano, d) then
				return
			elseif self:ZapACaminho(e) then
				LogComIntervalo("jinxresp:" .. tostring(e.charName), 3, string.format(
					"ROCKET ESPERANDO: o Zap ja esta a caminho de %s -- so gasta o "
					.. "foguete se ele sobreviver", tostring(e.charName)))
			elseif d <= self:AlcanceFoguete(e) + self:FolgaDePasso(e) then
				LogComIntervalo("jinxrtiro:" .. tostring(e.charName), 5, string.format(
					"ROCKET GUARDADO: %s esta a %d e o tiro alcanca %d (+%d de um passo) "
					.. "-- nao se perde abate continuando a atirar", tostring(e.charName),
					MathFloor(d), MathFloor(self:AlcanceFoguete(e)),
					MathFloor(self:FolgaDePasso(e))))
			elseif d <= self.W.Range and self:ZapMata(e, vida) then
				LogComIntervalo("jinxrzap:" .. tostring(e.charName), 5, string.format(
					"ROCKET GUARDADO: %s esta a %d, dentro do Zap (%d), e o Zap MATA "
					.. "-- deixa para ele", tostring(e.charName),
					MathFloor(d), MathFloor(self.W.Range)))
			elseif self:BloqueadoPorOutro(e, vida) then
			elseif LancarPrevisto(self.R.tecla, self.R, e, 3) then
				self._ultimoR = GetTickCount()
				Log(string.format(
					"ROCKET PARA MATAR: %s com %d de vida efetiva a %d unidades "
					.. "(alem do Zap, que alcanca %d) | o R tira %d",
					tostring(e.charName), MathFloor(vida), MathFloor(d),
					MathFloor(self.W.Range), MathFloor(dano)))
				return
			end
		end
	end
end
function Jinx:Defensivo()
	if not (self.menu.E.fuga:Value() and Pronto(_E)) then return end
	if GetTickCount() - (self._ultimoE or 0) < 1000 then return end
	for _, e in ipairs(Inimigos(self.E.Range)) do
		local p = e.pathing
		if p and p.isDashing and p.hasMovePath and p.endPos
			and DistSq(p.endPos, myHero.pos) < DistSq(e.pos, myHero.pos)
			and DistSq(p.endPos, myHero.pos) <= 400 * 400 then
			Control.CastSpell(self.E.tecla, p.endPos)
			self._ultimoE = GetTickCount()
			Log("CHOMPERS: on the landing point of " .. tostring(e.charName) .. "'s dash")
			return
		end
	end
end
local Ezreal = { charName = "Ezreal" }
Ezreal.Q = { slot = _Q, tecla = HK_Q,
	Type = 0, Delay = 0.25, Radius = 60, Range = 1150, Speed = 2000, Collision = true }
Ezreal.W = { slot = _W, tecla = HK_W,
	Type = 0, Delay = 0.25, Radius = 80, Range = 1150, Speed = 1700, Collision = false }
Ezreal.E = { slot = _E, tecla = HK_E, Range = 475 }
Ezreal.R = { slot = _R, tecla = HK_R,
	Type = 0, Delay = 1.00, Radius = 160, Range = 24000, Speed = 2000, Collision = false }
function Ezreal:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Mystic Shot"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = true})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Essence Flux"})
		menu.W:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.W:MenuElement({id = "poupar", name = "Save it when the target dies without it", value = true})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Trueshot Barrage"})
		menu.R:MenuElement({id = "abate", name = "Use to finish at range", value = true})
		menu.R:MenuElement({id = "alcance", name = "  up to", value = 3000, min = 1000, max = 24000, step = 500})
end
function Ezreal:Tick()
	if DeveEsperar() then return end
	if not (Combo() or Assedio()) then return end
	if Combo() and self.menu.W.combo:Value() and Pronto(_W) then
		local alvo = AlvoEm(self.W.Range)
		if alvo and not self:JaMorreSemW(alvo)
			and LancarPrevisto(self.W.tecla, self.W, alvo, 2) then
			LogComIntervalo("ezw", 3, "ESSENCE FLUX: em " .. tostring(alvo.charName))
		end
	end
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("ezq", 3, "MYSTIC SHOT: em " .. tostring(alvo.charName))
		end
	end
	if Combo() then self:Ultimate() end
end
function Ezreal:JaMorreSemW(alvo)
	if not self.menu.W.poupar:Value() then return false end
	local vida = (alvo.health or 0) + (alvo.shieldAD or 0)
	local aa = DanoDeAtaque(alvo)
	local alcanceAtaque = (myHero.range or 550) + (myHero.boundingRadius or 65)
	if aa and Dist(myHero.pos, alvo.pos) <= alcanceAtaque and aa > vida then return true end
	if Pronto(_Q) then
		local q = DanoDeHabilidade("Q", alvo)
		if q and q > vida then return true end
	end
	return false
end
function Ezreal:Ultimate()
	if not Core.PodeLancar(true) then return end
	if not (self.menu.R.abate:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 1500 then return end
	for _, e in ipairs(Inimigos(self.menu.R.alcance:Value())) do
		local dano = DanoDeHabilidade("R", e)
		if dano and e.health <= dano
			and LancarPrevisto(self.R.tecla, self.R, e, 3) then
			self._ultimoR = GetTickCount()
			Log(string.format("TRUESHOT PARA MATAR: %s com %d de vida, o R tira %d",
				tostring(e.charName), MathFloor(e.health), MathFloor(dano)))
			return
		end
	end
end
local Lucian = { charName = "Lucian" }
Lucian.Q = { slot = _Q, tecla = HK_Q, Range = 500 }
Lucian.W = { slot = _W, tecla = HK_W,
	Type = 0, Delay = 0.25, Radius = 55, Range = 1000, Speed = 1600, Collision = false }
Lucian.E = { slot = _E, tecla = HK_E, Range = 425 }
function Lucian:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Piercing Light"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = false})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Ardent Blaze"})
		menu.W:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.W:MenuElement({id = "soSemQ", name = "  only when Q is not ready", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Relentless Pursuit"})
		menu.E:MenuElement({id = "fuga", name = "Use to escape melee", value = true})
end
function Lucian:Tick()
	if DeveEsperar() then return end
	self:Defensivo()
	if not (Combo() or Assedio()) then return end
	local alcanceQ = self.Q.Range + (myHero.boundingRadius or 65)
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) then
		local alvo = AlvoEm(alcanceQ)
		if alvo then
			Control.CastSpell(self.Q.tecla, alvo)
			LogComIntervalo("lucq", 3, "PIERCING LIGHT: em " .. tostring(alvo.charName))
			return
		end
	end
	if Combo() and self.menu.W.combo:Value() and Pronto(_W) then
		if not (self.menu.W.soSemQ:Value() and Pronto(_Q)) then
			local alvo = AlvoEm(self.W.Range)
			if alvo and LancarPrevisto(self.W.tecla, self.W, alvo, 2) then
				LogComIntervalo("lucw", 3, "ARDENT BLAZE: em " .. tostring(alvo.charName))
			end
		end
	end
end
function Lucian:Defensivo()
	if not Core.PodeMover() then return end
	if not (self.menu.E.fuga:Value() and Pronto(_E)) then return end
	if GetTickCount() - (self._ultimoE or 0) < 1000 then return end
	for _, e in ipairs(Inimigos(300)) do
		if (e.range or 500) < 400 and ViradoParaMim(e) then
			local fuga = myHero.pos:Extended(e.pos, -self.E.Range)
			if not MapPosition:inWall(fuga) then
				Control.CastSpell(self.E.tecla, fuga)
				self._ultimoE = GetTickCount()
				Log("PURSUIT: escaping " .. tostring(e.charName))
				return
			end
		end
	end
end
local MissFortune = { charName = "MissFortune" }
MissFortune.Q = { slot = _Q, tecla = HK_Q, Range = 650 }
MissFortune.E = { slot = _E, tecla = HK_E,
	Type = 1, Delay = 0.25, Radius = 200, Range = 1150, Speed = MathHuge, Collision = false }
MissFortune.R = { slot = _R, tecla = HK_R, Range = 1350 }
function MissFortune:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Double Up"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = true})
		menu.Q:MenuElement({id = "ricochete", name = "Aim at a minion to bounce", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Make It Rain"})
		menu.E:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.E:MenuElement({id = "minimo", name = "  only with the target beyond", value = 400, min = 0, max = 1100, step = 50})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Bullet Time"})
		menu.R:MenuElement({id = "usar", name = "Use on its own in a group", value = false})
		menu.R:MenuElement({id = "quantos", name = "With N enemies together", value = 3, min = 1, max = 5, step = 1})
end
function MissFortune:Tick()
	if DeveEsperar() then return end
	if not (Combo() or Assedio()) then return end
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) then self:DoubleUp() end
	if Combo() and self.menu.E.combo:Value() and Pronto(_E) then
		local alvo = AlvoEm(self.E.Range)
		if alvo and Dist(myHero.pos, alvo.pos) > self.menu.E.minimo:Value()
			and TemManaPara(_E, _R)
			and LancarPrevisto(self.E.tecla, self.E, alvo, 2) then
			LogComIntervalo("mfe", 3, "MAKE IT RAIN: em " .. tostring(alvo.charName))
		end
	end
	if Combo() then self:Ultimate() end
end
function MissFortune:DoubleUp()
	local alvo = AlvoEm(self.Q.Range + 600)
	if not alvo then return end
	local alcance = self.Q.Range + (myHero.boundingRadius or 65)
	if self.menu.Q.ricochete:Value() then
		local ponte = self:MinionEntre(alvo, alcance)
		if ponte then
			Control.CastSpell(self.Q.tecla, ponte)
			LogComIntervalo("mfq", 3, string.format(
				"DOUBLE UP: no minion, para ricochetear em %s", tostring(alvo.charName)))
			return
		end
	end
	if Dist(myHero.pos, alvo.pos) <= alcance then
		Control.CastSpell(self.Q.tecla, alvo)
		LogComIntervalo("mfq", 3, "DOUBLE UP: direto em " .. tostring(alvo.charName))
	end
end
function MissFortune:MinionEntre(alvo, alcance)
	local melhor, maisPerto = nil, MathHuge
	pcall(function()
		local om = _G.SDK and _G.SDK.ObjectManager
		if not om then return end
		local ax, az = alvo.pos.x - myHero.pos.x, alvo.pos.z - myHero.pos.z
		local da = MathSqrt(ax * ax + az * az)
		if da < 1 then return end
		for _, m in ipairs(om:GetEnemyMinions(alcance, true, true)) do
			if m and m.valid and not m.dead then
				if Dist(m.pos, alvo.pos) <= 600 then
					local ex, ez = m.pos.x - myHero.pos.x, m.pos.z - myHero.pos.z
					local t = (ex * ax + ez * az) / da
					if t > 0 and t < da then
						local px, pz = ex - (ax / da) * t, ez - (az / da) * t
						local desvio = MathSqrt(px * px + pz * pz)
						if desvio <= (m.boundingRadius or 48) + 40 and t < maisPerto then
							melhor, maisPerto = m, t
						end
					end
				end
			end
		end
	end)
	return melhor
end
function MissFortune:Ultimate()
	if not Core.PodeLancar(true) then return end
	if not (self.menu.R.usar:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 3000 then return end
	local alvo = AlvoEm(self.R.Range)
	if not alvo then return end
	local juntos = QuantosPerto(alvo.pos, 400)
	if juntos >= self.menu.R.quantos:Value() then
		Control.CastSpell(self.R.tecla, alvo.pos)
		self._ultimoR = GetTickCount()
		Log(string.format("BULLET TIME: %d inimigos juntos", juntos))
	end
end
local Sivir = { charName = "Sivir" }
Sivir.Q = { slot = _Q, tecla = HK_Q,
	Type = 0, Delay = 0.25, Radius = 90, Range = 1250, Speed = 1450, Collision = false }
Sivir.W = { slot = _W, tecla = HK_W }
function Sivir:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Boomerang Blade"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = true})
		menu.Q:MenuElement({id = "maximo", name = "  up to a range of", value = 1000, min = 400, max = 1250, step = 50})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Ricochet"})
		menu.W:MenuElement({id = "combo", name = "Turn on in combo with a target in range", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Spell Shield"})
		menu.E:MenuElement({id = "aviso", name = "superEvade decides the E", value = true})
end
function Sivir:Tick()
	if DeveEsperar() then return end
	if not (Combo() or Assedio()) then return end
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) then
		local alvo = AlvoEm(self.menu.Q.maximo:Value())
		if alvo and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("sivq", 3, "BOOMERANG: em " .. tostring(alvo.charName))
		end
	end
	if Combo() and self.menu.W.combo:Value() and Pronto(_W) then
		local alcance = (myHero.range or 500) + (myHero.boundingRadius or 65)
		if AlvoEm(alcance) then Control.CastSpell(HK_W) end
	end
end
local Corki = { charName = "Corki" }
Corki.Q = { slot = _Q, tecla = HK_Q,
	Type = 1, Delay = 0.25, Radius = 275, Range = 950, Speed = 1100, Collision = false }
Corki.W = { slot = _W, tecla = HK_W, Range = 600 }
Corki.E = { slot = _E, tecla = HK_E, Range = 690 }
Corki.R = { slot = _R, tecla = HK_R, Range = 1225 }
function Corki:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Phosphorus Bomb"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Gatling Gun"})
		menu.E:MenuElement({id = "combo", name = "Use in combo with a target close", value = true})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Missile Barrage"})
		menu.R:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.R:MenuElement({id = "guardar", name = "Save the big rocket for a champion", value = true})
		menu.R:MenuElement({id = "abate", name = "Use to finish", value = true})
end
function Corki:Tick()
	if DeveEsperar() then return end
	if not (Combo() or Assedio()) then return end
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("corkiq", 3, "PHOSPHORUS: em " .. tostring(alvo.charName))
		end
	end
	if Combo() and self.menu.E.combo:Value() and Pronto(_E) then
		local alcance = (myHero.range or 550) + (myHero.boundingRadius or 65)
		if AlvoEm(alcance) then
			Control.CastSpell(HK_E)
			LogComIntervalo("corkie", 5, "GATLING: alvo no alcance de ataque")
		end
	end
	if Combo() then self:Foguete() end
end
function Corki:Foguete()
	if not (self.menu.R.combo:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 400 then return end
	local alvo = AlvoEm(self.R.Range)
	if not alvo then return end
	local cargas = 0
	pcall(function() cargas = myHero:GetSpellData(_R).ammo or 0 end)
	if self.menu.R.abate:Value() then
		local dano = DanoDeHabilidade("R", alvo)
		if dano and alvo.health <= dano then
			Control.CastSpell(self.R.tecla, alvo.pos)
			self._ultimoR = GetTickCount()
			Log(string.format("BARRAGE PARA MATAR: %s com %d de vida, o R tira %d (cargas %d)",
				tostring(alvo.charName), MathFloor(alvo.health), MathFloor(dano), cargas))
			return
		end
	end
	Control.CastSpell(self.R.tecla, alvo.pos)
	self._ultimoR = GetTickCount()
	LogComIntervalo("corkir", 3, string.format(
		"BARRAGE: em %s | %d cargas", tostring(alvo.charName), cargas))
end
local Twitch = { charName = "Twitch" }
Twitch.W = { slot = _W, tecla = HK_W,
	Type = 1, Delay = 0.25, Radius = 275, Range = 950, Speed = 1750, Collision = false }
Twitch.E = { slot = _E, tecla = HK_E, Range = 1200 }
Twitch.R = { slot = _R, tecla = HK_R }
function Twitch:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "W", name = "W -- Venom Cask"})
		menu.W:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.W:MenuElement({id = "assedio", name = "Use to harass", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Contaminate"})
		menu.E:MenuElement({id = "abate", name = "Use to finish", value = true})
		menu.E:MenuElement({id = "pilhas", name = "  or with N stacks on the target", value = 5, min = 2, max = 6, step = 1})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Spray and Pray"})
		menu.R:MenuElement({id = "usar", name = "Use with enemies lined up", value = true})
		menu.R:MenuElement({id = "quantos", name = "With N lined up", value = 2, min = 1, max = 5, step = 1})
end
function Twitch:Tick()
	if DeveEsperar() then return end
	if not (Combo() or Assedio()) then return end
	local usarW = (Combo() and self.menu.W.combo:Value())
		or (Assedio() and self.menu.W.assedio:Value())
	if usarW and Pronto(_W) then
		local alvo = AlvoEm(self.W.Range)
		if alvo and LancarPrevisto(self.W.tecla, self.W, alvo, 2) then
			LogComIntervalo("twitchw", 3, "VENOM CASK: em " .. tostring(alvo.charName))
		end
	end
	if Combo() then
		self:Contaminar()
		self:Ultimate()
	end
end
function Twitch:Contaminar()
	if not Pronto(_E) then return end
	if GetTickCount() - (self._ultimoE or 0) < 500 then return end
	for _, e in ipairs(Inimigos(self.E.Range)) do
		local pilhas = 0
		pcall(function()
			for i = 0, (e.buffCount or 0) do
				local b = e:GetBuff(i)
				if b and b.count and b.count > 0 and b.name
					and tostring(b.name):lower():find("twitchdeadlyvenom", 1, true) then
					pilhas = b.count
					return
				end
			end
		end)
		if pilhas > 0 then
			local dano = DanoDeHabilidade("E", e)
			local mata = self.menu.E.abate:Value() and dano and e.health <= dano
			local cheio = pilhas >= self.menu.E.pilhas:Value()
			if mata or cheio then
				Control.CastSpell(HK_E)
				self._ultimoE = GetTickCount()
				Log(string.format("CONTAMINATE: %s com %d pilhas | %s",
					tostring(e.charName), pilhas, mata and "abate" or "pilhas no teto"))
				return
			end
		end
	end
end
function Twitch:Ultimate()
	if not (self.menu.R.usar:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 3000 then return end
	local alvo = AlvoEm(1200)
	if not alvo then return end
	local alinhados = 0
	for _, e in ipairs(Inimigos(1400)) do
		if self:NaLinha(alvo, e) then alinhados = alinhados + 1 end
	end
	if alinhados >= self.menu.R.quantos:Value() then
		Control.CastSpell(HK_R)
		self._ultimoR = GetTickCount()
		Log(string.format("SPRAY AND PRAY: %d inimigos alinhados com %s",
			alinhados, tostring(alvo.charName)))
	end
end
function Twitch:NaLinha(alvo, e)
	local ax, az = alvo.pos.x - myHero.pos.x, alvo.pos.z - myHero.pos.z
	local m = MathSqrt(ax * ax + az * az)
	if m < 1 then return false end
	local ex, ez = e.pos.x - myHero.pos.x, e.pos.z - myHero.pos.z
	local t = (ex * ax + ez * az) / m
	if t < 0 then return false end
	local px, pz = ex - (ax / m) * t, ez - (az / m) * t
	return MathSqrt(px * px + pz * pz) <= 200
end
local Varus = { charName = "Varus" }
Varus.Q = { slot = _Q, tecla = HK_Q,
	Type = 0, Delay = 0, Radius = 70, Range = 925, Speed = 1900, Collision = false }
Varus.E = { slot = _E, tecla = HK_E,
	Type = 1, Delay = 0.25, Radius = 270, Range = 1060, Speed = 1750, Collision = false }
Varus.R = { slot = _R, tecla = HK_R,
	Type = 0, Delay = 0.25, Radius = 120, Range = 1250, Speed = 1500, Collision = false }
function Varus:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Piercing Arrow"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Hail of Arrows"})
		menu.E:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.E:MenuElement({id = "pilhas", name = "  only with N stacks on the target", value = 3, min = 1, max = 3, step = 1})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Chain of Corruption"})
		menu.R:MenuElement({id = "usar", name = "Use on its own in a group", value = true})
		menu.R:MenuElement({id = "quantos", name = "With N enemies together", value = 2, min = 1, max = 5, step = 1})
end
function Varus:Tick()
	if DeveEsperar() then return end
	if not (Combo() or Assedio()) then return end
	if Combo() and self.menu.E.combo:Value() and Pronto(_E) then
		local alvo = AlvoEm(self.E.Range)
		if alvo and self:Pilhas(alvo) >= self.menu.E.pilhas:Value()
			and LancarPrevisto(self.E.tecla, self.E, alvo, 2) then
			Log(string.format("HAIL OF ARROWS: %s com %d pilhas",
				tostring(alvo.charName), self:Pilhas(alvo)))
		end
	end
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("varq", 3, "PIERCING ARROW: em " .. tostring(alvo.charName))
		end
	end
	if Combo() then self:Ultimate() end
end
function Varus:Pilhas(unit)
	local n = 0
	pcall(function()
		for i = 0, (unit.buffCount or 0) do
			local b = unit:GetBuff(i)
			if b and b.count and b.count > 0 and b.name
				and tostring(b.name):lower():find("varuswdebuff", 1, true) then
				n = b.count
				return
			end
		end
	end)
	return n
end
function Varus:Ultimate()
	if not (self.menu.R.usar:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 2000 then return end
	local alvo = AlvoEm(self.R.Range)
	if not alvo then return end
	local juntos = QuantosPerto(alvo.pos, 350)
	if juntos >= self.menu.R.quantos:Value()
		and LancarPrevisto(self.R.tecla, self.R, alvo, 3) then
		self._ultimoR = GetTickCount()
		Log(string.format("CHAIN OF CORRUPTION: %d inimigos juntos", juntos))
	end
end
local KogMaw = { charName = "KogMaw" }
KogMaw.Q = { slot = _Q, tecla = HK_Q,
	Type = 0, Delay = 0.25, Radius = 70, Range = 1175, Speed = 1650, Collision = true }
KogMaw.W = { slot = _W, tecla = HK_W }
KogMaw.E = { slot = _E, tecla = HK_E,
	Type = 0, Delay = 0.25, Radius = 120, Range = 1200, Speed = 1400, Collision = false }
KogMaw.R = { slot = _R, tecla = HK_R,
	Type = 1, Delay = 1, Radius = 120, Range = 1300, Speed = MathHuge, Collision = false }
function KogMaw:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Caustic Spittle"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Bio-Arcane Barrage"})
		menu.W:MenuElement({id = "combo", name = "Turn on in combo with a target in range", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Void Ooze"})
		menu.E:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.E:MenuElement({id = "minimo", name = "  only with the target beyond", value = 500, min = 0, max = 1200, step = 50})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Living Artillery"})
		menu.R:MenuElement({id = "abate", name = "Use to finish", value = true})
		menu.R:MenuElement({id = "guardar", name = "  keep N charges", value = 1, min = 0, max = 5, step = 1})
end
function KogMaw:Tick()
	if DeveEsperar() then return end
	if not (Combo() or Assedio()) then return end
	if not Combo() then return end
	if self.menu.W.combo:Value() and Pronto(_W) then
		local alcance = (myHero.range or 500) + (myHero.boundingRadius or 65) + 130
		if AlvoEm(alcance) then Control.CastSpell(HK_W) end
	end
	if self.menu.Q.combo:Value() and Pronto(_Q) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("kogq", 3, "CAUSTIC SPITTLE: em " .. tostring(alvo.charName))
		end
	end
	if self.menu.E.combo:Value() and Pronto(_E) then
		local alvo = AlvoEm(self.E.Range)
		if alvo and Dist(myHero.pos, alvo.pos) > self.menu.E.minimo:Value()
			and LancarPrevisto(self.E.tecla, self.E, alvo, 2) then
			LogComIntervalo("koge", 3, "VOID OOZE: em " .. tostring(alvo.charName))
		end
	end
	self:Ultimate()
end
function KogMaw:Ultimate()
	if not (self.menu.R.abate:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 500 then return end
	local cargas = 0
	pcall(function() cargas = myHero:GetSpellData(_R).ammo or 0 end)
	if cargas <= self.menu.R.guardar:Value() then return end
	for _, e in ipairs(Inimigos(self.R.Range)) do
		local dano = DanoDeHabilidade("R", e)
		if dano and e.health <= dano
			and LancarPrevisto(self.R.tecla, self.R, e, 2) then
			self._ultimoR = GetTickCount()
			Log(string.format("LIVING ARTILLERY: %s com %d de vida, o R tira %d (cargas %d)",
				tostring(e.charName), MathFloor(e.health), MathFloor(dano), cargas))
			return
		end
	end
end
local Jhin = { charName = "Jhin" }
Jhin.Q = { slot = _Q, tecla = HK_Q, Range = 550 }
Jhin.W = { slot = _W, tecla = HK_W,
	Type = 0, Delay = 0.75, Radius = 40, Range = 2500, Speed = 5000, Collision = false }
Jhin.E = { slot = _E, tecla = HK_E, Range = 750 }
Jhin.R = { slot = _R, tecla = HK_R,
	Type = 0, Delay = 0.25, Radius = 80, Range = 3500, Speed = 5000, Collision = false }
function Jhin:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Dancing Grenade"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Deadly Flourish"})
		menu.W:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.W:MenuElement({id = "soMarcado", name = "  only on a marked target (stuns)", value = true})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Curtain Call"})
		menu.R:MenuElement({id = "aviso", name = "R stays manual: channelling is a fight read", value = true})
end
function Jhin:Tick()
	if DeveEsperar() then return end
	if not Combo() then return end
	if self.menu.Q.combo:Value() and Pronto(_Q) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo then
			Control.CastSpell(self.Q.tecla, alvo)
			LogComIntervalo("jhinq", 3, "DANCING GRENADE: em " .. tostring(alvo.charName))
		end
	end
	if self.menu.W.combo:Value() and Pronto(_W) then
		local alvo = AlvoEm(self.W.Range)
		if alvo then
			local marcado = TemBuff(alvo, "jhinespotteddebuff")
				or TemBuff(alvo, "jhinpassiveslow")
			if marcado or not self.menu.W.soMarcado:Value() then
				if LancarPrevisto(self.W.tecla, self.W, alvo, 2) then
					Log(string.format("DEADLY FLOURISH: em %s%s",
						tostring(alvo.charName), marcado and " (marcado, atordoa)" or ""))
				end
			end
		end
	end
end
local Kalista = { charName = "Kalista" }
Kalista.Q = { slot = _Q, tecla = HK_Q,
	Type = 0, Delay = 0.25, Radius = 40, Range = 1150, Speed = 2400, Collision = false }
Kalista.E = { slot = _E, tecla = HK_E, Range = 1000 }
Kalista.MARCA = "kalistaexpungemarker"
function Kalista:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Pierce"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = false})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Rend"})
		menu.E:MenuElement({id = "abate", name = "Charge when it kills", value = true})
		menu.E:MenuElement({id = "lancas", name = "  or with N spears stuck", value = 5, min = 2, max = 10, step = 1})
		menu.E:MenuElement({id = "onda", name = "Charge to clear a minion wave", value = true})
		menu.E:MenuElement({id = "ondaN", name = "  with N marked minions dying", value = 3, min = 2, max = 6, step = 1})
end
function Kalista:Tick()
	if DeveEsperar() then return end
	self:Rend()
	if not (Combo() or Assedio()) then return end
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) and TemManaPara(_Q, _E) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("kalq", 3, "PIERCE: em " .. tostring(alvo.charName))
		end
	end
end
function Kalista:Lancas(unit)
	local n = 0
	pcall(function()
		for i = 0, (unit.buffCount or 0) do
			local b = unit:GetBuff(i)
			if b and b.count and b.count > 0 and b.name
				and tostring(b.name):lower() == self.MARCA then
				n = b.count
				return
			end
		end
	end)
	return n
end
function Kalista:Rend()
	if not Pronto(_E) then return end
	if GetTickCount() - (self._ultimoE or 0) < 500 then return end
	if self.menu.E.abate:Value() then
		for _, e in ipairs(Inimigos(self.E.Range)) do
			local lancas = self:Lancas(e)
			if lancas > 0 then
				local dano = DanoDeHabilidade("E", e)
				if (dano and e.health <= dano) or lancas >= self.menu.E.lancas:Value() then
					Control.CastSpell(HK_E)
					self._ultimoE = GetTickCount()
					Log(string.format("REND: %s com %d lancas | %s",
						tostring(e.charName), lancas,
						(dano and e.health <= dano) and "abate" or "lancas no teto"))
					return
				end
			end
		end
	end
	if self.menu.E.onda:Value() then
		local morrem = 0
		pcall(function()
			local om = _G.SDK and _G.SDK.ObjectManager
			if not om then return end
			for _, m in ipairs(om:GetEnemyMinions(self.E.Range, true, true)) do
				if m and m.valid and not m.dead and self:Lancas(m) > 0 then
					local dano = DanoDeHabilidade("E", m)
					if dano and m.health <= dano then morrem = morrem + 1 end
				end
			end
		end)
		if morrem >= self.menu.E.ondaN:Value() then
			Control.CastSpell(HK_E)
			self._ultimoE = GetTickCount()
			Log(string.format("REND: %d minions marcados morrem juntos", morrem))
		end
	end
end
local Tristana = { charName = "Tristana" }
Tristana.Q = { slot = _Q, tecla = HK_Q }
Tristana.W = { slot = _W, tecla = HK_W, Range = 900 }
Tristana.E = { slot = _E, tecla = HK_E, Range = 550 }
Tristana.R = { slot = _R, tecla = HK_R, Range = 700 }
function Tristana:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Rapid Fire"})
		menu.Q:MenuElement({id = "combo", name = "Turn on in combo with a target in range", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Explosive Charge"})
		menu.E:MenuElement({id = "combo", name = "Use in combo", value = true})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Rocket Jump"})
		menu.W:MenuElement({id = "fuga", name = "Use to escape melee", value = true})
		menu.W:MenuElement({id = "vida", name = "  with my health below %", value = 30, min = 5, max = 70, step = 5})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Buster Shot"})
		menu.R:MenuElement({id = "abate", name = "Use ONLY to finish", value = true})
end
function Tristana:Tick()
	if DeveEsperar() then return end
	self:Fuga()
	if not Combo() then return end
	if self.menu.Q.combo:Value() and Pronto(_Q) then
		local alcance = (myHero.range or 550) + (myHero.boundingRadius or 65)
		if AlvoEm(alcance) then Control.CastSpell(HK_Q) end
	end
	if self.menu.E.combo:Value() and Pronto(_E) then
		local alvo = AlvoEm(self.E.Range)
		if alvo and not TemBuff(alvo, "tristanaecharge") then
			Control.CastSpell(HK_E, alvo)
			LogComIntervalo("trie", 3, "EXPLOSIVE CHARGE: cravado em " .. tostring(alvo.charName))
		end
	end
end
function Tristana:Abater()
	if not (self.menu.R.abate:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 1000 then return end
	for _, e in ipairs(Inimigos(self.R.Range)) do
		local dano = DanoDeHabilidade("R", e)
		local vida = (e.health or 0) + (e.shieldAD or 0) + (e.shieldAP or 0)
		if dano and vida <= dano then
			Control.CastSpell(self.R.tecla, e)
			self._ultimoR = GetTickCount()
			Log(string.format("BUSTER SHOT: %s com %d de vida efetiva e o R tira %d",
				tostring(e.charName), MathFloor(vida), MathFloor(dano)))
			return
		end
	end
end
function Tristana:Fuga()
	if not Core.PodeMover() then return end
	if not (self.menu.W.fuga:Value() and Pronto(_W)) then return end
	if GetTickCount() - (self._ultimoW or 0) < 2000 then return end
	local vida = (myHero.health / myHero.maxHealth) * 100
	if vida > self.menu.W.vida:Value() then return end
	for _, e in ipairs(Inimigos(300)) do
		if (e.range or 500) < 400 and ViradoParaMim(e) then
			local fuga = myHero.pos:Extended(e.pos, -self.W.Range)
			if not MapPosition:inWall(fuga) then
				Control.CastSpell(HK_W, fuga)
				self._ultimoW = GetTickCount()
				Log(string.format("ROCKET JUMP: fugindo de %s com %d%% de vida",
					tostring(e.charName), MathFloor(vida)))
				return
			end
		end
	end
end
local Draven = { charName = "Draven" }
Draven.Q = { slot = _Q, tecla = HK_Q }
Draven.W = { slot = _W, tecla = HK_W }
Draven.E = { slot = _E, tecla = HK_E,
	Type = 0, Delay = 0.25, Radius = 130, Range = 1050, Speed = 1400, Collision = false }
function Draven:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Spinning Axe"})
		menu.Q:MenuElement({id = "combo", name = "Keep axes spinning in combo", value = true})
		menu.Q:MenuElement({id = "quantos", name = "  how many axes to keep", value = 2, min = 1, max = 2, step = 1})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Blood Rush"})
		menu.W:MenuElement({id = "combo", name = "Use in combo to reach", value = true})
		menu.W:MenuElement({id = "minimo", name = "  only with the target beyond", value = 400, min = 0, max = 900, step = 50})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Stand Aside"})
		menu.E:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.E:MenuElement({id = "fuga", name = "Use on melee that closes in", value = true})
end
function Draven:Machados()
	local n = 0
	pcall(function()
		for i = 0, (myHero.buffCount or 0) do
			local b = myHero:GetBuff(i)
			if b and b.count and b.count > 0 and b.name
				and tostring(b.name):lower():find("dravenspinning", 1, true) then
				n = b.count
				return
			end
		end
	end)
	return n
end
function Draven:Tick()
	if DeveEsperar() then return end
	self:Defensivo()
	if not Combo() then return end
	if self.menu.Q.combo:Value() and Pronto(_Q) then
		if self:Machados() < self.menu.Q.quantos:Value() then
			local alcance = (myHero.range or 550) + (myHero.boundingRadius or 65)
			if AlvoEm(alcance) then
				Control.CastSpell(HK_Q)
				LogComIntervalo("dravq", 3, string.format(
					"SPINNING AXE: %d machados girando", self:Machados()))
			end
		end
	end
	if self.menu.W.combo:Value() and Pronto(_W) and Core.PodeMover() then
		local alvo = AlvoEm(900)
		if alvo and Dist(myHero.pos, alvo.pos) > self.menu.W.minimo:Value() then
			Control.CastSpell(HK_W)
			LogComIntervalo("dravw", 3, "BLOOD RUSH: alcancando " .. tostring(alvo.charName))
		end
	end
	if self.menu.E.combo:Value() and Pronto(_E) then
		local alvo = AlvoEm(self.E.Range)
		if alvo and LancarPrevisto(self.E.tecla, self.E, alvo, 2) then
			LogComIntervalo("drave", 3, "STAND ASIDE: em " .. tostring(alvo.charName))
		end
	end
end
function Draven:Defensivo()
	if not (self.menu.E.fuga:Value() and Pronto(_E)) then return end
	if GetTickCount() - (self._ultimoE or 0) < 1000 then return end
	for _, e in ipairs(Inimigos(400)) do
		if (e.range or 500) < 400 and ViradoParaMim(e)
			and LancarPrevisto(self.E.tecla, self.E, e, 2) then
			self._ultimoE = GetTickCount()
			Log("STAND ASIDE: knocking back " .. tostring(e.charName) .. " who closed in")
			return
		end
	end
end
local Urgot = { charName = "Urgot" }
Urgot.Q = { slot = _Q, tecla = HK_Q,
	Type = 1, Delay = 0.55, Radius = 210, Range = 800, Speed = MathHuge, Collision = false }
Urgot.W = { slot = _W, tecla = HK_W, Range = 500 }
Urgot.E = { slot = _E, tecla = HK_E,
	Type = 0, Delay = 0.45, Radius = 100, Range = 450, Speed = 1500, Collision = false }
Urgot.R = { slot = _R, tecla = HK_R,
	Type = 0, Delay = 0.5, Radius = 80, Range = 2500, Speed = 3200, Collision = false }
function Urgot:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Corrosive Charge"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = true})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Purge"})
		menu.W:MenuElement({id = "combo", name = "Turn on in combo with a target in range", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Disdain"})
		menu.E:MenuElement({id = "combo", name = "Use in combo", value = false})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Fear Beyond Death"})
		menu.R:MenuElement({id = "usar", name = "Use to execute", value = true})
		menu.R:MenuElement({id = "vida", name = "  with the target below %", value = 25, min = 10, max = 45, step = 5})
end
function Urgot:Tick()
	if DeveEsperar() then return end
	if not (Combo() or Assedio()) then return end
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("urgq", 3, "CORROSIVE: em " .. tostring(alvo.charName))
		end
	end
	if not Combo() then return end
	if self.menu.W.combo:Value() and Pronto(_W) then
		local alcance = self.W.Range + (myHero.boundingRadius or 65)
		if AlvoEm(alcance) then Control.CastSpell(HK_W) end
	end
	if self.menu.E.combo:Value() and Pronto(_E) and Core.PodeMover() then
		local alvo = AlvoEm(self.E.Range)
		if alvo and LancarPrevisto(self.E.tecla, self.E, alvo, 3) then
			Log("DISDAIN: dashing at " .. tostring(alvo.charName))
		end
	end
	self:Executar()
end
function Urgot:Executar()
	if not (self.menu.R.usar:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 2000 then return end
	for _, e in ipairs(Inimigos(self.R.Range)) do
		local pct = (e.maxHealth and e.maxHealth > 0) and (e.health / e.maxHealth * 100) or 100
		if pct <= self.menu.R.vida:Value()
			and LancarPrevisto(self.R.tecla, self.R, e, 3) then
			self._ultimoR = GetTickCount()
			Log(string.format("FEAR BEYOND DEATH: %s com %d%% de vida -- execucao",
				tostring(e.charName), MathFloor(pct)))
			return
		end
	end
end
local Graves = { charName = "Graves" }
Graves.Q = { slot = _Q, tecla = HK_Q,
	Type = 0, Delay = 0.25, Radius = 40, Range = 800, Speed = MathHuge, Collision = false }
Graves.W = { slot = _W, tecla = HK_W,
	Type = 1, Delay = 0.6, Radius = 250, Range = 950, Speed = 1500, Collision = false }
Graves.E = { slot = _E, tecla = HK_E, Range = 425 }
Graves.R = { slot = _R, tecla = HK_R,
	Type = 0, Delay = 0.25, Radius = 100, Range = 1000, Speed = 2100, Collision = false }
function Graves:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- End of the Line"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = true})
	menu:MenuElement({type = MENU, id = "W", name = "W -- Smoke Screen"})
		menu.W:MenuElement({id = "fuga", name = "Use on melee that closes in", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Quickdraw"})
		menu.E:MenuElement({id = "combo", name = "Use in combo to reach", value = true})
		menu.E:MenuElement({id = "minimo", name = "  only with the target beyond", value = 400, min = 0, max = 800, step = 50})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Collateral Damage"})
		menu.R:MenuElement({id = "abate", name = "Use to finish", value = true})
end
function Graves:Tick()
	if DeveEsperar() then return end
	self:Defensivo()
	if not (Combo() or Assedio()) then return end
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("gravq", 3, "END OF THE LINE: em " .. tostring(alvo.charName))
		end
	end
	if not Combo() then return end
	if self.menu.E.combo:Value() and Pronto(_E) and Core.PodeMover() then
		local alvo = AlvoEm(800)
		if alvo and Dist(myHero.pos, alvo.pos) > self.menu.E.minimo:Value() then
			local destino = myHero.pos:Extended(alvo.pos, self.E.Range)
			if not MapPosition:inWall(destino) then
				Control.CastSpell(HK_E, destino)
				LogComIntervalo("grave", 3, "QUICKDRAW: alcancando " .. tostring(alvo.charName))
			end
		end
	end
	self:Ultimate()
end
function Graves:Ultimate()
	if not (self.menu.R.abate:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 1500 then return end
	for _, e in ipairs(Inimigos(self.R.Range)) do
		local dano = DanoDeHabilidade("R", e)
		if dano and e.health <= dano
			and LancarPrevisto(self.R.tecla, self.R, e, 3) then
			self._ultimoR = GetTickCount()
			Log(string.format("COLLATERAL DAMAGE: %s com %d de vida, o R tira %d",
				tostring(e.charName), MathFloor(e.health), MathFloor(dano)))
			return
		end
	end
end
function Graves:Defensivo()
	if not (self.menu.W.fuga:Value() and Pronto(_W)) then return end
	if GetTickCount() - (self._ultimoW or 0) < 2000 then return end
	for _, e in ipairs(Inimigos(350)) do
		if (e.range or 500) < 400 and ViradoParaMim(e) then
			Control.CastSpell(HK_W, myHero.pos)
			self._ultimoW = GetTickCount()
			Log("SMOKE SCREEN: blinding " .. tostring(e.charName) .. " who closed in")
			return
		end
	end
end
local Quinn = { charName = "Quinn" }
Quinn.Q = { slot = _Q, tecla = HK_Q,
	Type = 0, Delay = 0.25, Radius = 60, Range = 1025, Speed = 1550, Collision = false }
Quinn.E = { slot = _E, tecla = HK_E, Range = 700 }
function Quinn:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Blinding Assault"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.Q:MenuElement({id = "assedio", name = "Use to harass", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Vault"})
		menu.E:MenuElement({id = "combo", name = "Use in combo", value = true})
		menu.E:MenuElement({id = "fuga", name = "Use on melee that closes in", value = true})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Behind Enemy Lines"})
		menu.R:MenuElement({id = "aviso", name = "R stays manual: it is a map decision", value = true})
end
function Quinn:Tick()
	if DeveEsperar() then return end
	self:Defensivo()
	if not (Combo() or Assedio()) then return end
	local usarQ = (Combo() and self.menu.Q.combo:Value())
		or (Assedio() and self.menu.Q.assedio:Value())
	if usarQ and Pronto(_Q) then
		local alvo = AlvoEm(self.Q.Range)
		if alvo and LancarPrevisto(self.Q.tecla, self.Q, alvo, 2) then
			LogComIntervalo("quinnq", 3, "BLINDING ASSAULT: em " .. tostring(alvo.charName))
		end
	end
	if Combo() and self.menu.E.combo:Value() and Pronto(_E) and Core.PodeMover() then
		local alvo = AlvoEm(self.E.Range)
		if alvo then
			Control.CastSpell(HK_E, alvo)
			LogComIntervalo("quinne", 3, "VAULT: em " .. tostring(alvo.charName))
		end
	end
end
function Quinn:Defensivo()
	if not Core.PodeMover() then return end
	if not (self.menu.E.fuga:Value() and Pronto(_E)) then return end
	if GetTickCount() - (self._ultimoE or 0) < 1500 then return end
	for _, e in ipairs(Inimigos(300)) do
		if (e.range or 500) < 400 and ViradoParaMim(e) then
			Control.CastSpell(HK_E, e)
			self._ultimoE = GetTickCount()
			Log("VAULT: vaulting over " .. tostring(e.charName))
			return
		end
	end
end
local Kindred = { charName = "Kindred" }
Kindred.Q = { slot = _Q, tecla = HK_Q, Range = 340 }
Kindred.W = { slot = _W, tecla = HK_W }
Kindred.E = { slot = _E, tecla = HK_E, Range = 500 }
Kindred.R = { slot = _R, tecla = HK_R, Range = 500 }
function Kindred:Init(menu)
	self.menu = menu
	menu:MenuElement({type = MENU, id = "Q", name = "Q -- Dance of Arrows"})
		menu.Q:MenuElement({id = "combo", name = "Use in combo (attack reset)", value = true})
	menu:MenuElement({type = MENU, id = "E", name = "E -- Mounting Dread"})
		menu.E:MenuElement({id = "combo", name = "Use in combo", value = true})
	menu:MenuElement({type = MENU, id = "R", name = "R -- Lambs Respite"})
		menu.R:MenuElement({id = "usar", name = "Use on its own to survive", value = true})
		menu.R:MenuElement({id = "vida", name = "  with my health below %", value = 15, min = 5, max = 40, step = 5})
end
function Kindred:Tick()
	if DeveEsperar() then return end
	self:Respiro()
	if not Combo() then return end
	if self.menu.E.combo:Value() and Pronto(_E) then
		local alvo = AlvoEm(self.E.Range)
		if alvo then
			Control.CastSpell(HK_E, alvo)
			LogComIntervalo("kine", 3, "MOUNTING DREAD: em " .. tostring(alvo.charName))
		end
	end
end
function Kindred:PosAtaque()
	if DeveEsperar() then return end
	if not Core.PodeMover() then return end
	if not Combo() then return end
	if not (self.menu.Q.combo:Value() and Pronto(_Q)) then return end
	local alcance = (myHero.range or 500) + (myHero.boundingRadius or 65)
	if not AlvoEm(alcance) then return end
	local destino = mousePos
	if MapPosition:inWall(destino) then return end
	Control.CastSpell(HK_Q, destino)
	LogComIntervalo("kinq", 3, "DANCE OF ARROWS: reset de ataque")
end
function Kindred:Respiro()
	if not Core.PodeLancar(true) then return end
	if not (self.menu.R.usar:Value() and Pronto(_R)) then return end
	if GetTickCount() - (self._ultimoR or 0) < 5000 then return end
	local vida = (myHero.health / myHero.maxHealth) * 100
	if vida > self.menu.R.vida:Value() then return end
	if #Inimigos(700) == 0 then return end
	Control.CastSpell(HK_R, myHero.pos)
	self._ultimoR = GetTickCount()
	Log(string.format("LAMBS RESPITE: minha vida em %d%%", MathFloor(vida)))
end
function Ashe:Abater() self:Ultimate(true) end
function Caitlyn:Abater() self:Ultimate() end
function Ezreal:Abater() self:Ultimate() end
function Jinx:Abater() self:Ultimate() end
function KogMaw:Abater() self:Ultimate() end
function Graves:Abater() self:Ultimate() end
local Modulos = {
	["Vayne"] = Vayne, ["Jinx"] = Jinx,
}
local function Carregar()
	ADC.Campeao = myHero.charName
	ADC.Modulo = Modulos[ADC.Campeao]
	if not ADC.Modulo then
		print("superADC v" .. VERSAO .. ": no module for " .. tostring(ADC.Campeao))
		return
	end
	ADC.menu = MenuElement({type = MENU, id = "superADC",
		name = "superADC " .. VERSAO .. " - " .. tostring(ADC.Campeao)})
	ADC.menu:MenuElement({id = "ligado", name = "Enabled", value = true})
	ADC.Modulo:Init(ADC.menu)
	ADC.menu:MenuElement({type = MENU, id = "Itens", name = "Active items"})
	ADC.menu.Itens:MenuElement({id = "usar", name = "Use Botrk, Cutlass and Youmuu", value = true})
	ADC.menu.Itens:MenuElement({id = "vida", name = "  with the target below %", value = 70, min = 10, max = 100, step = 5})
	ADC.menu:MenuElement({type = MENU, id = "Abate", name = "Long-range finisher"})
	ADC.menu.Abate:MenuElement({id = "usar", name = "Finisher ultimate outside combo", value = true})
	ADC.menu:MenuElement({type = MENU, id = "Torre", name = "Turret"})
	ADC.menu.Torre:MenuElement({id = "assedio", name = "Do not harass under enemy turret", value = true})
	Callback.Add("Tick", function()
		if not (ADC.menu.ligado:Value() and ADC.Modulo) then return end
		local ok, err = pcall(function() ADC.Modulo:Tick() end)
		if not ok then LogErro("Tick", err) end
		local ok3, err3 = pcall(function()
			if ADC.Modulo.Abater and ADC.menu.Abate.usar:Value() then ADC.Modulo:Abater() end
		end)
		if not ok3 then LogErro("Abater", err3) end
		local ok2, err2 = pcall(function()
			if Combo() then UsarItens(ADC.menu) end
		end)
		if not ok2 then LogErro("Itens", err2) end
	end)
	Callback.Add("Draw", function()
		if not (ADC.menu.ligado:Value() and ADC.Modulo) then return end
		if not ADC.Modulo.Draw then return end
		local ok, err = pcall(function() ADC.Modulo:Draw() end)
		if not ok then LogErro("Draw", err) end
	end)
	pcall(function()
		if ADC.Modulo.PosAtaque and _G.SDK and _G.SDK.Orbwalker
			and _G.SDK.Orbwalker.OnPostAttackTick then
			_G.SDK.Orbwalker:OnPostAttackTick(function(alvo)
				if not (ADC.menu.ligado:Value() and ADC.Modulo) then return end
				local ok, err = pcall(function() ADC.Modulo:PosAtaque(alvo) end)
				if not ok then LogErro("PosAtaque", err) end
			end)
		end
	end)
	Log("v" .. VERSAO .. " loaded for " .. ADC.Campeao
		.. " | superEvade API " .. (_G.superEvade and "already up"
			or "not up yet -- it publishes at the 30s mark"))
end
function OnLoad()
	DelayAction(function()
		local ok, err = pcall(Carregar)
		if not ok then LogErro("load", err) end
	end, 0.5)
end
