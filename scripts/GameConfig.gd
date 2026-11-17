class_name GameConfig
extends RefCounted
## ALL balance numbers live here. Tweak freely.

enum Element { PHYSICAL, ICE, ETHER, ELECTRIC }
enum Attack { SLAM, SWEEP, VOLLEY, CHARGE, ENRAGE, COMBO, QUAKE, LEAP, BEAM, ERUPTION }

# ---------------- Fight / camera ----------------
const FIGHT_TIME := 240.0
const ARENA_RADIUS := 24.0

# ---------------- Camera (mouse orbit, ZZZ style) ----------------
const CAM_DIST := 6.8               # default orbit distance (mouse wheel zooms)
const CAM_DIST_MIN := 3.6
const CAM_DIST_MAX := 11.0
const CAM_HEIGHT := 1.55            # orbit pivot height above the character's feet
const CAM_FOV := 60.0
const CAM_PITCH_DEFAULT := -0.22    # radians, negative = looking down
const CAM_PITCH_MIN := -1.05
const CAM_PITCH_MAX := 0.5
const MOUSE_SENS := 0.0026          # radians per pixel
const PAD_SENS := 3.0               # radians / second at full right-stick
const CAM_INVERT_Y := false
const CAM_FOLLOW := 11.0            # how tightly the pivot follows the character (higher = tighter)
const CAM_AUTO_FRAME := true        # gently swing toward the boss after ~1.5s without camera input
const CAM_SPRINT_FOV := 7.0
const CAM_LOCK_SHARPNESS := 6.0     # middle mouse / R3 lock-on tracking speed

# ---------------- Graphics ----------------
const GFX_VOLUMETRIC_FOG := true
const GFX_SSR := true               # wet-floor reflections
const GFX_SSAO := true
const GFX_POST_FX := true           # vignette / perfect-dodge grading / ult radial blur
const GFX_SHADOW_SPLITS := 4

# ---------------- Presentation / audio ----------------
const USE_3D_MODELS := true        # false = flat 2.5D art puppets (Puppet.gd)
const MUSIC_DB := -9.0
const SFX_DB := 0.0

# ---------------- Player ----------------
const PLAYER_SPEED := 8.5
const SPRINT_SPEED := 12.5          # hold Shift / RMB / A after a dodge (or while running)
const ATTACK_TIME := 0.32
const COMBO_RESET := 0.9
const LUNGE_SPEED := 14.0
const LUNGE_TIME := 0.12
const SEQ_MOVE_SPEED := 45.0
const HEAVY_HIT_STOP := 0.06
const HEAVY_SHAKE := 0.30
const HIT_I_FRAMES := 0.45

# ---------------- Dodge ----------------
const DODGE_SPEED := 20.0
const DODGE_TIME := 0.32
const DODGE_COOLDOWN := 0.5
const DODGE_END_I_FRAMES := 0.1
const PERFECT_TIMESCALE := 0.2
const PERFECT_DURATION := 1.1      # real seconds; Dodge Counter / Evasive Assist window
const PARRY_DAZE := 18.0            # Defensive Assist (swap during a gold flash)
const PARRY_DAMAGE := 120.0
const FOLLOWUP_WINDOW := 1.3        # real seconds to press attack for the Assist Follow-Up
const CHAIN_PROMPT_TIME := 3.0      # real seconds to pick a Chain Attack
const CHAIN_TIMESCALE := 0.04

# ---------------- Team systems ----------------
const SWAP_COOLDOWN := 1.0
const ENERGY_MAX := 100.0
const OFF_FIELD_ENERGY_REGEN := 2.0
const DECIBEL_MAX := 100.0
const DECIBEL_PER_HIT := 1.5
const DECIBEL_ASSIST := 10.0
const DECIBEL_CHAIN := 15.0
const ASSIST_BUFF := 0.25
const ASSIST_BUFF_TIME := 8.0
const ELLEN_MAX_STACKS := 6
const ELLEN_STACK_BONUS := 0.12

# ---------------- Damage model ----------------
const WEAKNESS_MULT := 1.25        # Ice / Ether
const CRIT_CHANCE := 0.2
const CRIT_MULT := 1.6
const DEF_DOWN_MULT := 1.25
const DEF_DOWN_TIME := 8.0
const STUN_DAMAGE_MULT := 1.8
const FREEZE_DAMAGE_MULT := 1.2
const DAZE_MAX := 100.0
const STUN_TIME := 8.0
const FREEZE_MAX := 100.0
const FREEZE_TIME := 3.0
const PULL_SPEED := 28.0
const PULL_TIME := 0.5

# ---------------- Boss ----------------
const BOSS_MAX_HP := 36000.0
const BOSS_RADIUS := 2.8
const BOSS_SPEED := 3.0
const BOSS_RECOVER_TIME := 1.0
const PHASE_ROAR_TIME := 1.6
const PHASE_THRESHOLDS := [0.66, 0.33]
const BOSS_ATTACK_CD := [1.2, 0.9, 0.6]          # per phase
const PERFECT_WINDOW := 0.35                      # last N sec before a hit = gold/red flash
const BOSS_TURN_SPEED := 2.6                      # rad/s while walking (heavy, readable turns)
const BOSS_MELEE_RANGE := 9.0                     # sweeps / combos are only picked inside this
const ATTACK_POOL := [
	[Attack.SLAM, Attack.SWEEP, Attack.COMBO, Attack.QUAKE],
	[Attack.SLAM, Attack.SWEEP, Attack.COMBO, Attack.QUAKE, Attack.VOLLEY, Attack.CHARGE, Attack.LEAP, Attack.BEAM],
	[Attack.SWEEP, Attack.COMBO, Attack.QUAKE, Attack.VOLLEY, Attack.CHARGE, Attack.LEAP, Attack.BEAM, Attack.ERUPTION, Attack.ERUPTION],
]
const MELEE_ATTACKS := [Attack.SWEEP, Attack.COMBO]
# Overhead smash: fists high, then a shockwave lands on the target's position.
const SLAM_DATA := {"tele": 1.1, "radius": 4.6, "dmg": 170.0, "reach": 11.0}
# Wide claw swipe (cone in front of the boss), random side.
const SWEEP_DATA := {"tele": 1.0, "radius": 8.6, "half_angle": 1.15, "dmg": 190.0}
# 3-hit string: right swipe, left swipe, overhead slam. Each hit flashes gold.
const COMBO_DATA := {"hits": [0.9, 1.6, 2.6], "radius": 7.2, "half_angle": 0.95, "dmg": 120.0, "slam_radius": 4.2, "slam_dmg": 170.0}
# Alternating stomps, each sends out an expanding shockwave ring. Dodge through them.
const QUAKE_DATA := {"first": 1.0, "rings": [2, 3, 4], "gap": 0.8, "speed": 11.0, "width": 1.1, "dmg": 110.0}
# Jumps off-screen, the landing zone hunts the player, then a meteor landing.
const LEAP_DATA := {"crouch": 0.6, "air": 1.5, "lock": 0.45, "height": 10.0, "radius": 5.6, "dmg": 240.0}
# Charges the core, then sweeps a beam across a wide arc. RED flash: cannot be parried.
const BEAM_DATA := {"tele": 1.3, "sweep": 2.3, "arc": 2.5, "length": 30.0, "width": 1.7, "dmg": 140.0}
# Punches the ground: corrupted spikes erupt under the player again and again.
const ERUPTION_DATA := {"count": [0, 6, 8], "interval": 0.3, "tele": 0.85, "radius": 2.3, "dmg": 130.0}
const CHARGE_DATA := {"tele": 1.2, "width": 5.6, "time": 0.45, "dmg": 230.0, "overshoot": 3.0, "recover": 1.6}
const VOLLEY_DATA := {"tele": 0.85, "count": [3, 5, 7], "spread": 0.9, "speed": 12.0, "dmg": 95.0, "homing": 1.7, "homing_time": 0.9}
# Leaps to the arena centre and detonates the whole arena. RED flash: dodge it exactly.
const ENRAGE_DATA := {"tele": 3.2, "dmg": 750.0, "first_delay": 12.0, "interval": 32.0}

# ---------------- Score ----------------
const SCORE_PER_DAMAGE := 0.12
const MULT_MAX := 5.0
const COMBO_TIMEOUT := 3.0
const SCORE_PER_SEC_LEFT := 40.0
const SCORE_DAMAGE_TAKEN_PENALTY := 0.5
const ASSIST_POINTS := 3000
const CHAIN_POINTS := 4000
const PERFECT_POINTS := 1500
const GRADE_THRESHOLDS := [["B", 10000.0], ["A", 16000.0], ["S", 24000.0]]

# ---------------- Chain attack ----------------
# Each character has its own "chain" rows below. Up to three chains per stun (each agent once).

# ---------------- Characters ----------------
# Step rows: [time, damage, daze, freeze, shake]
const ELLEN := {
	"name": "ELLEN", "element": Element.ICE,
	"color": Color(0.55, 0.85, 1.0), "accent": Color(1.0, 1.0, 1.0),
	"hp": 1100.0, "range": 3.4, "combo": [55.0, 60.0, 70.0, 140.0],
	"daze": 1.5, "freeze": 14.0, "energy_hit": 4.0, "ex_cost": 50.0,
	"stun_bonus": 1.5, "field_buff": 0.0, "stand": 3.9,
	"weapon": Vector3(0.14, 0.14, 1.7),
	"ex": [[0.15, 90.0, 3.0, 10.0, 0.0], [0.30, 90.0, 3.0, 10.0, 0.0], [0.45, 90.0, 3.0, 10.0, 0.0], [0.75, 220.0, 8.0, 20.0, 0.35]],
	"ex_len": 1.1,
	"ult": [[0.2, 130.0, 2.0, 6.0, 0.1], [0.4, 130.0, 2.0, 6.0, 0.1], [0.6, 130.0, 2.0, 6.0, 0.1], [0.8, 130.0, 2.0, 6.0, 0.1], [1.0, 130.0, 2.0, 6.0, 0.1], [1.5, 480.0, 10.0, 30.0, 0.6]],
	"ult_len": 2.1,
	"assist": [[0.1, 150.0, 4.0, 10.0, 0.1], [0.3, 200.0, 4.0, 10.0, 0.2]],
	"assist_len": 0.7,
	"chain": [[0.12, 180.0, 0.0, 15.0, 0.2], [0.35, 180.0, 0.0, 15.0, 0.2], [0.7, 520.0, 0.0, 35.0, 0.7]],
	"chain_len": 1.1,
}
const NICOLE := {
	"name": "NICOLE", "element": Element.ETHER,
	"color": Color(1.0, 0.45, 0.8), "accent": Color(1.0, 0.85, 0.3),
	"hp": 950.0, "range": 5.0, "combo": [32.0, 32.0, 38.0, 65.0],
	"daze": 2.0, "freeze": 0.0, "energy_hit": 5.0, "ex_cost": 50.0,
	"stun_bonus": 1.0, "field_buff": 0.15, "stand": -1.0,
	"weapon": Vector3(0.3, 0.3, 0.9),
	"ex": [[0.2, 70.0, 6.0, 0.0, 0.1], [0.45, 70.0, 6.0, 0.0, 0.1], [0.7, 120.0, 8.0, 0.0, 0.3]],
	"ex_len": 1.1,
	"ult": [[0.25, 60.0, 4.0, 0.0, 0.1], [0.5, 60.0, 4.0, 0.0, 0.1], [0.75, 60.0, 4.0, 0.0, 0.1], [1.0, 60.0, 4.0, 0.0, 0.1], [1.25, 60.0, 4.0, 0.0, 0.1], [1.6, 320.0, 12.0, 0.0, 0.6]],
	"ult_len": 2.0,
	"assist": [[0.1, 70.0, 5.0, 0.0, 0.1], [0.3, 90.0, 5.0, 0.0, 0.2]],
	"assist_len": 0.7,
	"chain": [[0.15, 120.0, 0.0, 0.0, 0.2], [0.4, 120.0, 0.0, 0.0, 0.2], [0.75, 300.0, 0.0, 0.0, 0.6]],
	"chain_len": 1.1,
}
const ANBY := {
	"name": "ANBY", "element": Element.ELECTRIC,
	"color": Color(1.0, 0.92, 0.3), "accent": Color(0.3, 0.9, 1.0),
	"hp": 1000.0, "range": 3.6, "combo": [38.0, 38.0, 42.0, 56.0],
	"daze": 5.0, "freeze": 0.0, "energy_hit": 5.0, "ex_cost": 50.0,
	"stun_bonus": 1.0, "field_buff": 0.0, "stand": 3.5,
	"weapon": Vector3(0.12, 0.12, 1.3),
	"ex": [[0.1, 40.0, 12.0, 0.0, 0.05], [0.2, 40.0, 12.0, 0.0, 0.05], [0.3, 40.0, 12.0, 0.0, 0.05], [0.4, 40.0, 12.0, 0.0, 0.05], [0.7, 80.0, 18.0, 0.0, 0.3]],
	"ex_len": 1.0,
	"ult": [[0.2, 90.0, 8.0, 0.0, 0.1], [0.4, 90.0, 8.0, 0.0, 0.1], [0.6, 90.0, 8.0, 0.0, 0.1], [0.8, 90.0, 8.0, 0.0, 0.1], [1.0, 90.0, 8.0, 0.0, 0.1], [1.6, 260.0, 22.0, 0.0, 0.6]],
	"ult_len": 2.1,
	"assist": [[0.1, 60.0, 15.0, 0.0, 0.1], [0.3, 80.0, 15.0, 0.0, 0.2]],
	"assist_len": 0.7,
	"chain": [[0.1, 140.0, 0.0, 0.0, 0.2], [0.3, 140.0, 0.0, 0.0, 0.2], [0.65, 340.0, 0.0, 0.0, 0.65]],
	"chain_len": 1.0,
}

static func element_color(e: int) -> Color:
	match e:
		Element.ICE:
			return Color(0.45, 0.92, 1.0)
		Element.ETHER:
			return Color(1.0, 0.4, 0.85)
		Element.ELECTRIC:
			return Color(1.0, 0.95, 0.35)
	return Color(1.0, 1.0, 1.0)
