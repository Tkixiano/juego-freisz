"""Enumerate Windows DirectShow cameras in OpenCV CAP_DSHOW index order.

Uses Windows COM through ctypes; no extra Python package is required.
Run: python -m vision.list_cameras
"""
import ctypes as ct
import json
import sys
import uuid


def list_cameras():
    if sys.platform != "win32":
        raise OSError("DirectShow enumeration requires Windows")

    class GUID(ct.Structure):
        _fields_ = [("data", ct.c_ubyte * 16)]

        def __init__(self, value):
            super().__init__()
            self.data[:] = uuid.UUID(value).bytes_le

    class VARIANT(ct.Structure):
        # VARIANT contains a union including a two-pointer record on Win64.
        _fields_ = [("vt", ct.c_ushort), ("reserved", ct.c_ushort * 3),
                    ("value", ct.c_void_p), ("record_info", ct.c_void_p)]

    ole = ct.OleDLL("ole32")
    automation = ct.OleDLL("oleaut32")
    ole.CoInitialize.argtypes = [ct.c_void_p]
    ole.CoCreateInstance.argtypes = [ct.POINTER(GUID), ct.c_void_p, ct.c_ulong,
                                    ct.POINTER(GUID), ct.POINTER(ct.c_void_p)]
    automation.VariantClear.argtypes = [ct.POINTER(VARIANT)]

    def call(pointer, slot, result_type, argtypes, *args):
        table = ct.cast(pointer, ct.POINTER(ct.POINTER(ct.c_void_p))).contents
        return ct.WINFUNCTYPE(result_type, ct.c_void_p, *argtypes)(table[slot])(pointer, *args)

    def release(pointer):
        if pointer:
            call(pointer, 2, ct.c_ulong, [])

    def check(result):
        if result < 0:
            raise OSError(f"DirectShow COM HRESULT 0x{result & 0xffffffff:08x}")

    initialized = ole.CoInitialize(None)
    check(initialized)
    device_enum, enum = ct.c_void_p(), ct.c_void_p()
    try:
        check(ole.CoCreateInstance(GUID("62be5d10-60eb-11d0-bd3b-00a0c911ce86"), None, 1,
                                  GUID("29840822-5b84-11d0-bd3b-00a0c911ce86"), ct.byref(device_enum)))
        result = call(device_enum, 3, ct.c_long,
                      [ct.POINTER(GUID), ct.POINTER(ct.c_void_p), ct.c_ulong],
                      ct.byref(GUID("860bb310-5d01-11d0-bd3b-00a0c911ce86")), ct.byref(enum), 0)
        check(result)
        if result == 1:
            return []
        devices = []
        while True:
            moniker, fetched = ct.c_void_p(), ct.c_ulong()
            result = call(enum, 3, ct.c_long,
                          [ct.c_ulong, ct.POINTER(ct.c_void_p), ct.POINTER(ct.c_ulong)],
                          1, ct.byref(moniker), ct.byref(fetched))
            check(result)
            if result == 1:
                break
            bag = ct.c_void_p()
            try:
                check(call(moniker, 9, ct.c_long,
                           [ct.c_void_p, ct.c_void_p, ct.POINTER(GUID), ct.POINTER(ct.c_void_p)],
                           None, None, ct.byref(GUID("55272a00-42cb-11ce-8135-00aa004bb851")), ct.byref(bag)))
                device = {"index": len(devices)}
                for key in ("FriendlyName", "DevicePath"):
                    value = VARIANT()
                    try:
                        status = call(bag, 3, ct.c_long,
                                      [ct.c_wchar_p, ct.POINTER(VARIANT), ct.c_void_p],
                                      key, ct.byref(value), None)
                        if status >= 0 and value.vt == 8 and value.value:
                            device[key] = ct.wstring_at(value.value)
                    finally:
                        automation.VariantClear(ct.byref(value))
                devices.append(device)
            finally:
                release(bag)
                release(moniker)
        return devices
    finally:
        release(enum)
        release(device_enum)
        ole.CoUninitialize()


if __name__ == "__main__":
    print(json.dumps(list_cameras(), indent=2, ensure_ascii=False))
