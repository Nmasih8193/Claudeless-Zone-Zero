DEADLY ASSAULT PROTOTYPE (Godot 4.4+, Forward+ renderer; made with 4.7)
Open project.godot, let the editor import art/ and audio/, press F5, then F / ENTER.

CONTROLS (Zenless Zone Zero PC defaults, Xbox-layout pad in brackets)
  Mouse [Right Stick]      orbit the camera around your agent   Wheel  zoom
  WASD [Left Stick]        move (relative to the camera)
  Shift / RMB [A]          dodge  -  keep holding to sprint
  LMB [X]                  basic attack (hold to keep the combo going)
  E [Y]                    special attack  /  EX special when energy is full
  Q [RT]                   ultimate (Decibel 100%)
  Space / C [RB / LB]      switch to next / previous agent
  MMB [R3]                 lock-on toggle
  Chain Attack picker      LMB or Q [LB] = left agent,  RMB or E [RB] = right agent
  F / Enter [A]            interact (start / retry)
  Left Alt                 summon mouse cursor (hold)
  G [View]                 Proxy Handbook (controls + boss guide)
  J [D-Pad Left]           Inter-Knot (forum posts with tips)
  Tab [LT] (hold)          Shortcut Wheel; with the wheel open, X on the pad = Squad
  T                        Squad overview
  Esc [Start]              pause                 R  retry from the pause / results screen

COMBAT
  GOLD flash on the boss  -> swap in for a Defensive Assist, then LMB for the Assist Follow-Up.
  RED flash               -> unblockable, dodge it.
  Perfect dodge (dodge as a hit is about to land) -> slow-mo:
      LMB = Dodge Counter, Space / C = Evasive Assist.
  Fill the Daze bar to stun the boss: the Chain Attack picker opens (up to 3 chains).

THE CORRUPTED COLOSSUS (procedurally rigged, spring-animated)
  Phase 1: Overhead Smash, Claw Sweep, 3-hit String, Quake Stomps (expanding rings)
  Phase 2: + Homing Orbs, Shoulder Charge, Meteor Leap (zone hunts you), Core Beam (RED)
  Phase 3: + Spike Eruption (chases you) and Annihilation every ~30s (arena-wide, RED)

Tuning:  scripts/GameConfig.gd   balance, camera (sensitivity, invert, auto-framing), graphics
                                 toggles (GFX_*), boss attack data, USE_3D_MODELS, MUSIC_DB, SFX_DB
         scripts/CameraRig.gd    orbit camera, lock-on, cinematics, shake
         scripts/Boss.gd         attack timelines        scripts/BossModel.gd  boss rig + poses
         scripts/Arena.gd        sky, lighting, city     scripts/Shaders.gd    all custom shaders
         scripts/Model3D.gd      agent models + spring physics (hair, tails, skirts, weapons)
         scripts/Sfx.gd          synthesised sound effects + music loader (audio/bgm.mp3)

If the frame rate is low, turn off GFX_VOLUMETRIC_FOG / GFX_SSR / GFX_SSAO in GameConfig.gd.
