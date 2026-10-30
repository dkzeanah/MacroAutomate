"""Absolute-file entry point so every client starts with a predictable import path."""
import runpy
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
runpy.run_module('bridge.controller.tool_server',run_name='__main__')
