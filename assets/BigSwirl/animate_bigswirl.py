"""Animates the Big Swirl's arms in Blender and bakes the cycle for Roblox. Run after build_bigswirl.py, in the same
Blender session (it uses its set_arm_pose and pose constants):
    exec(open(r"<repo>/assets/BigSwirl/animate_bigswirl.py").read())

One cycle per arm, 30 fps: down into the trough, scoop, swing up, a soft underhand lob, back to rest, with
anticipation and follow-through. Each key is (frame, arm pitch, cup tilt) in degrees: the pitch lifts the
arm about its shoulder (positive = up), the tilt leans the cup's opening away from straight up (positive = outward,
the way the scoop flies). Both stay inside the poses build_bigswirl.py checked for collisions.

Markers (time in seconds from the cycle's start):
    Scooped  the cup leaves the mix with a scoop in it: the game shows the scoop in the flavour that will fly
    Release  the scoop leaves the cup on the way up of the lob: the game starts the scoop's flight here

The animation reaches Roblox through export_bigswirl.py (one FBX per arm for the Animation Editor). The bake
(arm_cycle.json in ASSET_DIR) is for the game code: the marker times, where each arm releases its scoop, and per frame
the shoulder and wrist turns relative to the rest pose (shoulder = pitch - rest pitch, wrist = (pitch + tilt) -
(rest pitch + rest tilt), in degrees, positive lifting the arm and tipping the cup outward).
"""

import json
import math
import os

import bpy

FPS = 30
SP = math.degrees(SCOOP_PITCH)  # noqa: F821 (from build_bigswirl.py)
REST_P, REST_T = math.degrees(IDLE_PITCH), math.degrees(IDLE_CUP_TILT)  # noqa: F821

# (frame, pitch, tilt)
KEYS = [
    (0, REST_P, REST_T),
    (6, REST_P + 6, 0),  # anticipation: a little lift, the cup levels
    (14, SP, -10),  # dives down, the cup's front edge digs in
    (17, SP + 2.5, -12),  # bounces off the mix
    (21, SP, -4),  # settles in
    (24, SP, -12),
    (30, SP + 0.5, 15),  # scoops through the mix
    (34, SP + 6, 8),
    (42, REST_P + 3, -6),  # swings up, overshooting a little
    (46, REST_P - 1, 0),
    (49, REST_P, -2),
    # the throw: a soft underhand lob (since the kill test of 13.11.2026; before, the arm pulled back up to 37 degrees and
    # whipped down, so the scoop left a cup going down and seemed to jump): it dips a little below rest, swings up and
    # out and lets go on the way up, the cup tipping outward, so the scoop carries on the arm's own arc
    (57, REST_P - 9, -12),  # dips back and down, gathering
    (61, REST_P - 11, -16),  # lowest point
    (66, REST_P - 2, 20),  # swings up and out
    (68, REST_P + 3, 42),  # RELEASE on the way up: the cup tips out
    (71, REST_P + 7, 48),  # follows through, not higher than 32 degrees
    (76, REST_P + 4, 25),  # eases back
    (82, REST_P - 1, 8),
    (86, REST_P + 1, 14),
    (90, REST_P, REST_T),  # rest
]
MARKERS = {"Scooped": 31, "Release": 68}
LENGTH = KEYS[-1][0]

scene = bpy.context.scene
scene.render.fps = FPS
scene.frame_start = 0
scene.frame_end = LENGTH


def clear_animation(ob):
    if ob.animation_data:
        ob.animation_data_clear()


def key_arm(n, offset=0):
    """Keys arm n's cycle starting at frame `offset`; its scoop pops in at Scooped and is gone at Release."""
    shoulder = bpy.data.objects[f"LauncherArm_{n}"]
    wrist = bpy.data.objects[f"Arm{n}_Wrist"]
    ball = bpy.data.objects[f"Arm{n}_Scoop"]
    for ob in (shoulder, wrist, ball):
        clear_animation(ob)
    for frame, pitch, tilt in KEYS:
        set_arm_pose(n, math.radians(pitch), math.radians(tilt))  # noqa: F821
        shoulder.keyframe_insert("rotation_euler", index=1, frame=frame + offset)
        wrist.keyframe_insert("rotation_euler", index=1, frame=frame + offset)
    # the scoop: empty cup until Scooped (a quick pop), gone at Release
    for frame, scale in ((0, 0.0), (MARKERS["Scooped"] - 1, 0.0), (MARKERS["Scooped"] + 2, 1.15), (MARKERS["Scooped"] + 4, 1.0),
                         (MARKERS["Release"], 1.0), (MARKERS["Release"] + 1, 0.0), (LENGTH, 0.0)):
        ball.scale = (scale, scale, scale)
        ball.keyframe_insert("scale", frame=frame + offset)
    for ob in (shoulder, wrist):
        for fc in ob.animation_data.action.fcurves if hasattr(ob.animation_data.action, "fcurves") else []:
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
                kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
    set_arm_pose(n, IDLE_PITCH, IDLE_CUP_TILT)  # noqa: F821


def bake(n=1):
    """Samples arm n's cycle at every frame, relative to the rest pose (see the module doc)."""
    shoulder = bpy.data.objects[f"LauncherArm_{n}"]
    wrist = bpy.data.objects[f"Arm{n}_Wrist"]
    frames = []
    for f in range(0, LENGTH + 1):
        scene.frame_set(f)
        pitch = -math.degrees(shoulder.rotation_euler[1])
        wrist_turn = math.degrees(wrist.rotation_euler[1])  # = pitch + tilt
        frames.append(
            {
                "t": round(f / FPS, 4),
                "shoulder": round(pitch - REST_P, 3),
                "wrist": round(wrist_turn - (REST_P + REST_T), 3),
            }
        )
    # where the scoop leaves each arm at Release, from the machine's centre on the ground, in the imported model's
    # Roblox axes (checked on its bones in Studio: X = -Blender X, Y up, Z = Blender Y, so the sign looks along -Z):
    # the flight starts there
    scene.frame_set(MARKERS["Release"])
    release = {}
    for arm in arm_yaws:  # noqa: F821 (from build_bigswirl.py)
        p = bpy.data.objects[f"Arm{arm}_Muzzle"].matrix_world.translation
        release[str(arm)] = [round(-p.x, 3), round(p.z, 3), round(p.y, 3)]
    scene.frame_set(0)
    return {
        "fps": FPS,
        "length": LENGTH / FPS,
        "rest": {"pitch": REST_P, "tilt": REST_T},
        "markers": {name: round(frame / FPS, 4) for name, frame in MARKERS.items()},
        "releasePoints": release,
        "frames": frames,
    }


def write_bake(data):
    path = os.path.join(ASSET_DIR, "arm_cycle.json")  # noqa: F821 (from build_bigswirl.py)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    return path


for n in arm_yaws:  # noqa: F821
    key_arm(n)
for name, frame in MARKERS.items():
    m = scene.timeline_markers.get(name) or scene.timeline_markers.new(name, frame=frame)
    m.frame = frame
print("baked to", write_bake(bake(1)))
