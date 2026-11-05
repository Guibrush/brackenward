# Asset manifest schema

`art/manifest.json` and `audio/manifest.json` are the contract between generation
and the gate. A file without an entry is unreviewed; an entry without a file is a
lie. `scripts/gate/assets.ps1` and `scripts/gate/audio.ps1` check both directions.

## art/manifest.json

```jsonc
{
  "version": 1,
  "palette": ["#1a1c2c", "#5d275d", "#b13e53"],
  "assets": [
    {
      "id": "hero",                    // unique, stable, used in filenames
      "type": "character",             // character | tile | ui | vfx | prop
      "file": "assets/art/characters/hero/idle/south.png",
      "width": 32,                     // verified against the PNG header
      "height": 32,
      "directions": 4,                 // declared, checked against frames
      "actions": ["idle", "walk"],
      "frames": [                      // every declared frame must exist
        "assets/art/characters/hero/idle/south.png",
        "assets/art/characters/hero/walk/south/01.png"
      ],
      "placeholder": false,            // true is allowed until G4
      "license": "generated: PixelLab, commercial use",
      "prompt": "small red slime, front view, flat shading",
      "generator": "pixellab/create_image_pixflux",
      "cost": "1 generation"
    }
  ]
}
```

### Rules

- `id` and `file` are required. Everything else is metadata: useful, but the gate
  does not depend on it.
- `type` is recommended (`character`, `tile`, `ui`, `vfx`, `prop`, `probe`) and is
  used for filtering and review, not for validation.
- `width` and `height` are optional. When present they are checked against the PNG
  header; a descriptive `size` string like `"64x64"` is not checked.
- `frames` is either a **list of frame files** or a **count** of frames inside
  `file`. A count is not treated as a path.
- `placeholder: true` exempts an asset from the palette check in G2.5. Placeholders
  are not shipping assets; G4.8 is the criterion that forbids them surviving.
- `license` is required from the first entry, including probes. Retro-fitting
  licences to 200 assets is the least pleasant week of a project.
- `status` is free text (`probe`, `raw-evidence`, `anchor`, `final`). It is for
  humans and reviewers, and carries no gate behaviour.

## audio/manifest.json

```jsonc
{
  "version": 1,
  "entries": [
    {
      "id": "sfx_coin_pickup_01",
      "kind": "sfx",                   // sfx | music
      "file": "assets/audio/sfx/sfx_coin_pickup_01.wav",
      "loop": false,
      "target_lufs": -16,              // defaults: sfx -16, music -18
      "max_seconds": 2,
      "license": "generated: ElevenLabs, commercial use",
      "prompt": "retro arcade coin pickup, short bright blip",
      "generator": "elevenlabs/text_to_sound_effects",
      "cost": "1 generation"
    },
    {
      "id": "mus_forest_calm",
      "kind": "music",
      "file": "assets/audio/music/mus_forest_calm.ogg",
      "loop": true,
      "target_lufs": -18,
      "license": "generated: ElevenLabs, commercial use",
      "prompt": "calm 8-bit chiptune exploration theme",
      "generator": "elevenlabs/music",
      "cost": "10s music"
    }
  ]
}
```

### Rules

- `kind` decides the expected codec: `sfx` must be `pcm_s16le` in WAV, `music`
  must be Vorbis in OGG. Both at 48 kHz.
- `loop: true` triggers the seam measurement. The measurement happens on the
  shipped file, after trimming and crossfading — never on the raw generator
  output.
- `target_lufs` overrides the default. Tolerance is ±2 LU (`gate.config.ps1`).
- `max_seconds` is optional but recommended for one-shots; it catches a generator
  returning a 30-second clip when you asked for a 1-second blip.

## Sprite sheets → SpriteFrames

A character can ship as a grid sheet instead of individual frame files. Add a
`sheet` block to its manifest entry and `scripts/art/build_frames.gd` builds a
Godot `SpriteFrames` resource beside it:

```jsonc
{
  "id": "hero",
  "type": "character",
  "file": "assets/art/characters/hero/sheet.png",
  "width": 128, "height": 64,
  "sheet": {
    "file": "assets/art/characters/hero/sheet.png",
    "frame_width": 32, "frame_height": 32,
    "columns": 4, "rows": 2,
    "animations": {
      "idle": { "row": 0, "frames": 4, "fps": 8,  "loop": true },
      "walk": { "row": 1, "frames": 4, "fps": 10, "loop": true }
    }
  }
}
```

```powershell
godot --headless --path . --script res://scripts/art/build_frames.gd
```

Writes `sheet_frames.tres` next to the sheet. Deterministic: the same sheet and
manifest always produce the same resource, so it is safe to commit and diff.

The tool reads the PNG from disk rather than through Godot's import pipeline, so
it works immediately after generation without opening the editor.

## Who writes these

`art/pixel` writes `art/manifest.json`. `audio/sfx` and `audio/music` write
disjoint entries in `audio/manifest.json`, coordinated by `studio-lead` because
two agents cannot append to one file safely.
