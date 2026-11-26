# Video analysis

Adds a left sidebar entry that parses a video into 1 fps frames and generates multi-frame, sequence-aware descriptions with a vision-capable model.

## What it does

- Accepts a video by drag-and-drop/pick (browser upload) or by disk path.
- Extracts frames at 1 frame per second with ffmpeg (scaled to a 1024 px long edge).
- Picks a vision-capable model automatically: your current model when it accepts images, otherwise the first registered provider/model whose `inputModalities` include `image`.
- Streams the frames to the model in overlapping sequence windows (default 6 frames, stride 4) so each description is produced from a *sequence*, capturing motion, actions, and scene changes across time rather than describing frames in isolation.
- Shows one temporally-aware description per window in the panel.

## Usage

1. Open the **Video analysis** entry in the left sidebar.
2. Drop/pick a video, or switch to **Disk path** and enter a path to a video file.
3. Click **Analyze video**.

## Limitations

- Requires a vision-capable model to be configured. If none is, the panel reports it and nothing is analyzed.
- Uploads are capped at 512 MB; analysis is capped at 120 frames (~2 minutes at 1 fps) to bound cost and time.
- Frame images are kept only for the duration of the request (stored as transient model attachments); the panel shows the descriptions, not a frame gallery.
