"""Resolve existing local DeepSeek credentials without creating another key store."""
import ctypes
import json
import os
from pathlib import Path

def windows_key(target):
    if os.name != 'nt': return ''
    from ctypes import wintypes
    class Credential(ctypes.Structure):
        _fields_ = [('Flags', wintypes.DWORD), ('Type', wintypes.DWORD), ('TargetName', wintypes.LPWSTR),
            ('Comment', wintypes.LPWSTR), ('LastWritten', wintypes.FILETIME), ('CredentialBlobSize', wintypes.DWORD),
            ('CredentialBlob', ctypes.POINTER(ctypes.c_ubyte)), ('Persist', wintypes.DWORD),
            ('AttributeCount', wintypes.DWORD), ('Attributes', ctypes.c_void_p),
            ('TargetAlias', wintypes.LPWSTR), ('UserName', wintypes.LPWSTR)]
    library = ctypes.WinDLL('advapi32', use_last_error=True)
    pointer = ctypes.POINTER(Credential)()
    library.CredReadW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(ctypes.POINTER(Credential))]
    library.CredFree.argtypes = [ctypes.c_void_p]
    if not library.CredReadW(target, 1, 0, ctypes.byref(pointer)): return ''
    try:
        raw = ctypes.string_at(pointer.contents.CredentialBlob, pointer.contents.CredentialBlobSize)
        try:
            return raw.decode('utf-16-le' if raw[1:2] == b'\x00' else 'utf-8').rstrip('\x00')
        except UnicodeError:
            return ''
    finally:
        library.CredFree(pointer)

def resolve():
    if os.environ.get('DEEPSEEK_API_KEY'): return os.environ['DEEPSEEK_API_KEY'], 'environment'
    for target in ('MacroAutomator/DeepSeek', 'Cutline/DeepSeek'):
        value = windows_key(target)
        if value: return value, 'Windows Credential Manager: '+target
    from .common import ROOT
    project = Path(os.environ.get('CUTLINE_ROOT', ROOT.parents[2]/'avideditor'))
    try:
        value = json.loads((project/'data'/'studio'/'llm_credentials.json').read_text(encoding='utf-8')).get('deepseek_api_key', '')
        if value: return str(value), 'existing Cutline credential cache'
    except (OSError, ValueError, AttributeError): pass
    return '', 'not configured'
