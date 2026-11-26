"""Create a small real video for the native GUI integration test."""
import subprocess
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from media_analysis import engine_python


def main():
    if len(sys.argv) == 3:
        return subprocess.call([engine_python(sys.argv[1]), __file__, sys.argv[1], sys.argv[2], '--engine'])
    import cv2
    import numpy as np
    output = Path(sys.argv[2])
    output.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(str(output), cv2.VideoWriter_fourcc(*'mp4v'), 24, (320, 180))
    if not writer.isOpened():
        raise RuntimeError('Could not create the video verification fixture')
    try:
        for index in range(72):
            image = np.full((180, 320, 3), (20, 20, 220) if index < 36 else (20, 220, 20), np.uint8)
            x = index * 3 % 240
            cv2.rectangle(image, (x, 50), (x + 40, 100), (255, 255, 255), -1)
            writer.write(image)
    finally:
        writer.release()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
