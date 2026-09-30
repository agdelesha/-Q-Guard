import struct
import sys
from pathlib import Path

png = Path(sys.argv[1]).read_bytes()
chunk = b"ic10" + struct.pack(">I", len(png) + 8) + png
Path(sys.argv[2]).write_bytes(b"icns" + struct.pack(">I", len(chunk) + 8) + chunk)
