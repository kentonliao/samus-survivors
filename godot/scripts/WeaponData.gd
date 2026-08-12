class_name WeaponData
## 武器/被動/進化資料表（index.html WEAPON_DEFS / PASSIVE_DEFS 同構移植）
## 鍵名刻意保留 HTML 版 camelCase，便於逐欄對照除錯

const WEAPON_ORDER: Array[String] = [
	"powerBeam", "iceBeam", "waveBeam", "plasmaBeam", "spazerBeam", "missile",
	"bombTrail", "powerBomb", "screwAttack", "grappleBeam", "spiderMine", "echoPulse",
]

const WEAPONS := {
	"powerBeam": {
		"name": "力量光束", "category": "projectile", "color": "#dffcff", "shape": "bolt",
		"baseDmg": 8.0, "dmgPerLv": 3.2, "baseCd": 0.42, "cdPerLv": -0.03, "minCd": 0.15,
		"baseCount": 1.0, "countEvery": 2.0, "basePierce": 1.0, "speed": 520.0,
		"evoPartner": "overloadCapacitor",
		"evo": {"id": "novaBeam", "name": "Nova Beam 新星光束", "color": "#ffc830",
			"desc": "冷卻大幅縮短，化為高頻貫穿雷射連射。",
			"dmgMult": 2.2, "cdMult": 0.5, "pierceAdd": 6.0},
	},
	"iceBeam": {
		"name": "冰凍光束", "category": "projectile", "color": "#8fe8ff", "shape": "shard",
		"baseDmg": 6.0, "dmgPerLv": 2.6, "baseCd": 0.5, "cdPerLv": -0.025, "minCd": 0.18,
		"baseCount": 1.0, "countEvery": 3.0, "basePierce": 1.0, "speed": 420.0,
		"slowBase": 0.28, "slowPerLv": 0.02,
		"evoPartner": "piercingCore",
		"evo": {"id": "absoluteZero", "name": "Absolute Zero 絕對零度", "color": "#5cd8ff",
			"category": "beam_continuous", "range": 300.0,
			"desc": "凝聚成絕對零度射線，持續凍結並灼蝕目標。",
			"dmgMult": 2.0, "freeze": true},
	},
	"waveBeam": {
		"name": "波動光束", "category": "directional", "color": "#c86bff", "wavy": true, "shape": "ribbon",
		"baseDmg": 7.0, "dmgPerLv": 2.8, "baseCd": 0.48, "cdPerLv": -0.025, "minCd": 0.2,
		"baseCount": 1.0, "countEvery": 1.0, "basePierce": 5.0, "speed": 480.0,
		"evoPartner": "multiLockModule",
		"evo": {"id": "cascadeBeam", "name": "Cascade Beam 連鎖波動", "color": "#e3b8ff",
			"desc": "光束陣列加密，自動旋轉掃射全場。",
			"dmgMult": 1.8, "cdMult": 0.7, "countAdd": 4.0, "pierceAdd": 6.0, "spinPerShot": 0.7},
	},
	"plasmaBeam": {
		"name": "電漿光束", "category": "beam_continuous", "color": "#ff8fe0", "range": 260.0,
		"baseDmg": 15.0, "dmgPerLv": 6.5,
		"evoPartner": "overloadCapacitor",
		"evo": {"id": "plasmaStorm", "name": "Plasma Storm 電漿風暴", "color": "#ff4fd8",
			"category": "orbit_field",
			"desc": "化為環繞玩家的旋轉電漿力場，360度持續灼燒。",
			"dmgMult": 1.1, "radius": 130.0},
	},
	"spazerBeam": {
		"name": "分光光束", "category": "projectile", "color": "#ffe27a", "spreadAngle": 0.4, "shape": "star",
		"baseDmg": 6.0, "dmgPerLv": 2.3, "baseCd": 0.55, "cdPerLv": -0.028, "minCd": 0.2,
		"baseCount": 3.0, "countEvery": 2.0, "basePierce": 1.0, "speed": 480.0,
		"evoPartner": "multiLockModule",
		"evo": {"id": "prismaticSpazer", "name": "Prismatic Spazer 稜光散射", "color": "#ffe14f",
			"category": "radial_burst",
			"desc": "化為全圓周彈幕齊射，如綻放的稜鏡光環。",
			"dmgMult": 1.6},
	},
	"missile": {
		"name": "飛彈發射器", "category": "homing", "color": "#ffb03d",
		"baseDmg": 20.0, "dmgPerLv": 9.0, "baseCd": 1.1, "cdPerLv": -0.07, "minCd": 0.4,
		"baseCount": 1.0, "countEvery": 2.0, "maxCount": 4.0, "splashRadius": 34.0,
		"evoPartner": "piercingCore",
		"evo": {"id": "superMissileBarrage", "name": "Super Missile Barrage 超級飛彈群", "color": "#ff7a30",
			"desc": "齊射式貫穿飛彈群，爆炸後產生二次分裂彈頭。",
			"dmgMult": 1.8, "countAdd": 3.0, "splashRadiusAdd": 50.0},
	},
	"bombTrail": {
		"name": "炸彈軌跡", "category": "placed_bomb", "color": "#ffcf3d",
		"baseDmg": 13.0, "dmgPerLv": 5.5, "dropInterval": 0.65, "dropIntervalPerLv": -0.03,
		"fuseTime": 0.8, "blastRadius": 42.0,
		"evoPartner": "criticalSensor",
		"evo": {"id": "chainReaction", "name": "Chain Reaction 連鎖爆破", "color": "#ffae3c",
			"desc": "炸彈間會互相引爆，一觸即發連環大爆炸。",
			"dmgMult": 1.6, "blastRadiusAdd": 20.0, "chainTrigger": true},
	},
	"powerBomb": {
		"name": "強力炸彈", "category": "delayed_nova", "color": "#ff5b3d",
		"baseDmg": 42.0, "dmgPerLv": 17.0, "cooldown": 4.0, "cdPerLv": -0.2, "minCooldown": 1.6,
		"radius": 110.0, "radiusPerLv": 6.0, "delay": 0.6,
		"evoPartner": "reserveTank",
		"evo": {"id": "zeroCountdown", "name": "Zero Countdown 歸零倒數", "color": "#fff340",
			"desc": "清屏核彈，引爆瞬間造成大量傷害並回復能量。",
			"dmgMult": 2.0, "radiusAdd": 80.0, "healOnDetonate": 0.15, "countAdd": 2.0},
	},
	"screwAttack": {
		"name": "螺旋攻擊", "category": "orbit_aura", "color": "#c58bff",
		"baseDmg": 11.0, "dmgPerLv": 4.3, "radius": 55.0, "radiusPerLv": 3.0,
		"evoPartner": "boosterCoil",
		"evo": {"id": "shinesparkFury", "name": "Shinespark Fury 閃光衝刺・狂", "color": "#ff7ae0",
			"desc": "能量光環大幅擴張，並定期爆發強力衝擊波。",
			"dmgMult": 1.8, "radiusAdd": 35.0, "pulseBurst": true},
	},
	"grappleBeam": {
		"name": "抓鉤光束", "category": "chain", "color": "#4fd8ff",
		"baseDmg": 9.0, "dmgPerLv": 3.6, "baseCd": 0.6, "cdPerLv": -0.02,
		"chainCount": 2.0, "chainCountEvery": 3.0, "chainRange": 200.0,
		"evoPartner": "multiLockModule",
		"evo": {"id": "chainLightningArray", "name": "Chain Lightning Array 連鎖電網", "color": "#6ce8ff",
			"desc": "連鎖跳數大幅提升，近乎連結全場敵人。",
			"dmgMult": 1.7, "chainCountAdd": 6.0},
	},
	"spiderMine": {
		"name": "磁力地雷", "category": "mine", "color": "#ffb830",
		"baseDmg": 26.0, "dmgPerLv": 11.0, "dropInterval": 1.3, "dropIntervalPerLv": -0.06,
		"triggerRadius": 42.0, "blastRadius": 56.0, "maxMines": 3.0, "maxMinesEvery": 3.0,
		"evoPartner": "magnetCore",
		"evo": {"id": "gravityWellMine", "name": "Gravity Well Mine 重力井地雷", "color": "#a860ff",
			"desc": "觸發時先形成黑洞吸聚敵人，再引爆大範圍傷害。",
			"dmgMult": 1.8, "blastRadiusAdd": 25.0, "pullEffect": true},
	},
	"echoPulse": {
		"name": "音波脈衝", "category": "pulse", "color": "#7ff0ff",
		"baseDmg": 15.0, "dmgPerLv": 5.5, "cooldown": 1.6, "cdPerLv": -0.08, "minCooldown": 0.7,
		"maxRadius": 140.0, "radiusPerLv": 6.0,
		"evoPartner": "criticalSensor",
		"evo": {"id": "resonanceCascade", "name": "Resonance Cascade 共鳴連鎖", "color": "#3ee8c8",
			"desc": "脈衝命中敵人時有機率觸發額外連鎖脈衝。",
			"dmgMult": 1.6, "chainPulse": true},
	},
}

const PASSIVE_ORDER: Array[String] = [
	"energyTank", "magnetCore", "reserveTank", "boosterCoil",
	"multiLockModule", "overloadCapacitor", "piercingCore", "criticalSensor",
]

const PASSIVES := {
	"energyTank": {"name": "能量儲存槽", "desc": "最大能量 +20，立即回復。"},
	"magnetCore": {"name": "磁力核心", "desc": "拾取／磁吸範圍大幅提升。"},
	"reserveTank": {"name": "備用能量槽", "desc": "HP危急時觸發護盾與回復（限次數）。"},
	"boosterCoil": {"name": "加速線圈", "desc": "移動速度提升。"},
	"multiLockModule": {"name": "多重鎖定", "desc": "所有武器 +1 目標／彈幕／連鎖數。"},
	"overloadCapacitor": {"name": "超載電容", "desc": "所有武器冷卻時間縮短。"},
	"piercingCore": {"name": "貫穿核心", "desc": "所有可貫穿武器 +1 貫穿次數。"},
	"criticalSensor": {"name": "暴擊感測", "desc": "攻擊有機率造成2倍暴擊傷害。"},
}


static func num(d: Dictionary, k: String, dflt := 0.0) -> float:
	return float(d.get(k, dflt))
