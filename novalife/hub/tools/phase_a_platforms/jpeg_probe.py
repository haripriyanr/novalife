#!/usr/bin/env python3
"""JPEG structure and EXIF probe for Phase A.

Everything here is read straight out of the file bytes with the standard
library. There is no "is this 75 or 80?" answer handed back by any library:
the quality factor is estimated by matching the quantisation tables actually
in the file against the JPEG Annex K tables, and the estimate is reported as
an estimate.

What this module gives you:
  * which SOF marker the file uses (baseline / progressive / other), the
    per-component sampling factors (the subsampling), and the image size
  * every quantisation table in the file, plus an Annex-K quality estimate
  * every APPn/COM segment, and, for APP1 Exif, the decoded TIFF IFDs:
    tag count, tag names present, and the orientation value
"""
from __future__ import annotations

import struct
from typing import Any

# ---------------------------------------------------------------- constants

# Standard JPEG zigzag scan order, as (row, col). DQT tables are stored in this
# order, so a table read from the file must be reordered before it is compared
# with anything printed in natural order.
ZIGZAG_ORDER = [
    (0, 0), (0, 1), (1, 0), (2, 0), (1, 1), (0, 2), (0, 3), (1, 2),
    (2, 1), (3, 0), (4, 0), (3, 1), (2, 2), (1, 3), (0, 4), (0, 5),
    (1, 4), (2, 3), (3, 2), (4, 1), (5, 0), (6, 0), (5, 1), (4, 2),
    (3, 3), (2, 4), (1, 5), (0, 6), (0, 7), (1, 6), (2, 5), (3, 4),
    (4, 3), (5, 2), (6, 1), (7, 0), (7, 1), (6, 2), (5, 3), (4, 4),
    (3, 5), (2, 6), (1, 7), (2, 7), (3, 6), (4, 5), (5, 4), (6, 3),
    (7, 2), (7, 3), (6, 4), (5, 5), (4, 6), (3, 7), (4, 7), (5, 6),
    (6, 5), (7, 4), (7, 5), (6, 6), (5, 7), (6, 7), (7, 6), (7, 7),
]

# Same order expressed as flat indices into a natural-order 8x8 table.
ZIGZAG_TO_NATURAL = [r * 8 + c for r, c in ZIGZAG_ORDER]
NATURAL_TO_ZIGZAG = [0] * 64
for _z, _n in enumerate(ZIGZAG_TO_NATURAL):
    NATURAL_TO_ZIGZAG[_n] = _z

# JPEG Annex K luminance quantisation table, natural (row-major) order.
ANNEX_K_LUMA = [
    16, 11, 10, 16, 24, 40, 51, 61,
    12, 12, 14, 19, 26, 58, 60, 55,
    14, 13, 16, 24, 40, 57, 69, 56,
    14, 17, 22, 29, 51, 87, 80, 62,
    18, 22, 37, 56, 68, 109, 103, 77,
    24, 35, 55, 64, 81, 104, 113, 92,
    49, 64, 78, 87, 103, 121, 120, 101,
    72, 92, 95, 98, 112, 100, 103, 99,
]

# JPEG Annex K chrominance quantisation table, natural (row-major) order.
ANNEX_K_CHROMA = [
    17, 18, 24, 47, 99, 99, 99, 99,
    18, 21, 26, 66, 99, 99, 99, 99,
    24, 26, 56, 99, 99, 99, 99, 99,
    47, 66, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
]

SOF_MARKERS = {
    0xC0: "baseline_dct",
    0xC1: "extended_sequential_dct",
    0xC2: "progressive_dct",
    0xC3: "lossless",
    0xC5: "differential_sequential_dct",
    0xC6: "differential_progressive_dct",
    0xC7: "differential_lossless",
    0xC9: "extended_sequential_dct_arithmetic",
    0xCA: "progressive_dct_arithmetic",
    0xCB: "lossless_arithmetic",
    0xCD: "differential_sequential_dct_arithmetic",
    0xCE: "differential_progressive_dct_arithmetic",
    0xCF: "differential_lossless_arithmetic",
}

# Markers with no length field: they stand alone.
STANDALONE = set(range(0xD0, 0xD8)) | {0xD8, 0xD9, 0x01}

APP_MARKER_NAMES = {0xE0 + i: f"APP{i}" for i in range(16)}

# EXIF field types: (name, size of one value)
EXIF_TYPES = {
    1: ("BYTE", 1),
    2: ("ASCII", 1),
    3: ("SHORT", 2),
    4: ("LONG", 4),
    5: ("RATIONAL", 8),
    6: ("SBYTE", 1),
    7: ("UNDEFINED", 1),
    8: ("SSHORT", 2),
    9: ("SLONG", 4),
    10: ("SRATIONAL", 8),
    11: ("FLOAT", 4),
    12: ("DOUBLE", 8),
}

# A working subset of the EXIF/TIFF tag names that matter to this project.
# Keys are the two-byte tag numbers (element ids).
EXIF_TAG_NAMES = {
    0x000B: "ProcessingSoftware",
    0x00FE: "NewSubfileType",
    0x0100: "ImageWidth",
    0x0101: "ImageLength",
    0x010E: "ImageDescription",
    0x010F: "Make",
    0x0110: "Model",
    0x0112: "Orientation",
    0x011A: "XResolution",
    0x011B: "YResolution",
    0x0128: "ResolutionUnit",
    0x0131: "Software",
    0x0132: "DateTime",
    0x013B: "Artist",
    0x013C: "HostComputer",
    0x013E: "WhitePoint",
    0x0201: "JPEGInterchangeFormat",
    0x0202: "JPEGInterchangeFormatLength",
    0x0211: "YCbCrCoefficients",
    0x0213: "YCbCrPositioning",
    0x8298: "Copyright",
    0x829A: "ExposureTime",
    0x8769: "ExifIFD",
    0x8822: "ExposureProgram",
    0x8825: "GPSInfoIFD",
    0x9000: "ExifVersion",
    0x9003: "DateTimeOriginal",
    0x9004: "CreateDate",
    0x9101: "ComponentsConfiguration",
    0x9201: "ShutterSpeedValue",
    0x9202: "ApertureValue",
    0x9204: "ExposureCompensation",
    0x9207: "MeteringMode",
    0x9209: "Flash",
    0x920A: "FocalLength",
    0x927C: "MakerNote",
    0x9286: "UserComment",
    0x9290: "SubSecTime",
    0x9291: "SubSecTimeOriginal",
    0xA000: "FlashpixVersion",
    0xA001: "ColorSpace",
    0xA002: "PixelXDimension",
    0xA003: "PixelYDimension",
    0xA005: "InteroperabilityIFD",
    0xA20E: "FocalPlaneXResolution",
    0xA20F: "FocalPlaneYResolution",
    0xA210: "FocalPlaneResolutionUnit",
    0xA217: "SensingMethod",
    0xA300: "FileSource",
    0xA301: "SceneType",
    0xA401: "CustomRendered",
    0xA402: "ExposureMode",
    0xA403: "WhiteBalance",
    0xA406: "SceneCaptureType",
    0xA420: "ImageUniqueID",
    0xA430: "CameraOwnerName",
    0xA431: "BodySerialNumber",
    0xA432: "LensSpecification",
    0xA433: "LensMake",
    0xA434: "LensModel",
    0xA435: "LensSerialNumber",
    0x9C9B: "XPTitle",
    0x9C9C: "XPComment",
    0x9C9D: "XPAuthor",
    0x9C9E: "XPKeywords",
    0x9C9F: "XPSubject",
}

# Tags that, if they survive, can identify a patient, a device or a workflow.
# This is the list the report checks tag-by-tag.
IDENTITY_TAGS = [
    "ImageDescription", "Artist", "Copyright", "XPTitle", "XPComment",
    "XPAuthor", "XPKeywords", "XPSubject", "HostComputer", "ImageUniqueID",
    "CameraOwnerName", "BodySerialNumber", "LensModel", "LensSerialNumber",
    "MakerNote", "UserComment", "ProcessingSoftware", "Software",
    "Make", "Model", "DateTime", "DateTimeOriginal", "CreateDate",
]

ORIENTATION_VALUES = {
    1: "top-left (normal)",
    2: "top-right (mirrored horizontal)",
    3: "bottom-right (rotated 180)",
    4: "bottom-left (mirrored vertical)",
    5: "left-top (mirrored + 90 CW)",
    6: "right-top (rotated 90 CW)",
    7: "right-bottom (mirrored + 270 CW)",
    8: "left-bottom (rotated 270 CW)",
}

SAMPLING_LABELS = {
    (1, 1): "4:4:4",
    (2, 1): "4:2:2",
    (2, 2): "4:2:0",
    (4, 1): "4:1:1",
    (2, 4): "4:4:0",
    (1, 2): "4:4:1",
    (1, 4): "4:1:1(vertical)",
}


# ---------------------------------------------------------------- helpers


def _u16(data: bytes, off: int) -> int:
    return struct.unpack_from(">H", data, off)[0]


def _u32(data: bytes, off: int) -> int:
    return struct.unpack_from(">I", data, off)[0]


def _table_to_grid(table: list[int]) -> list[list[int]]:
    """A 64-entry natural-order table as an 8x8 grid, for readable output."""
    return [table[8 * r: 8 * r + 8] for r in range(8)]


def zigzag_to_natural(table: list[int]) -> list[int]:
    """A 64-entry zigzag-order table (as stored in DQT) to natural order."""
    if len(table) != 64:
        raise ValueError(f"expected 64 values, got {len(table)}")
    out = [0] * 64
    for z, n in enumerate(ZIGZAG_TO_NATURAL):
        out[n] = table[z]
    return out


def estimate_quality(table: list[int]) -> dict[str, Any]:
    """Estimate the IJG quality factor that produced one quantisation table.

    Estimates only, never a fact: libjpeg, Pillow and the phone encoders all
    scale the Annex K tables slightly differently, so treat the number as
    "consistent with Annex K scaling at Q=..." and check the tables.

    Method: pick the Annex K table (luma or chroma) whose overall magnitudes
    are closest, then take the median of value/base over the coefficients with
    a large base and a value above the floor of 1. That median is the IJG
    scale factor s. s <= 100 means Q >= 50 (s = 200 - 2Q); s > 100 means
    Q < 50 (s = 5000 / Q).

    Returns a dict with the estimate, the table it was matched against, the
    number of coefficients used, and whether the fit is plausible.

    `table` is in zigzag order, exactly as it is stored in the DQT segment.
    """
    natural_to_zigzag = NATURAL_TO_ZIGZAG
    luma_zigzag = [ANNEX_K_LUMA[i] for i in ZIGZAG_TO_NATURAL]
    chroma_zigzag = [ANNEX_K_CHROMA[i] for i in ZIGZAG_TO_NATURAL]

    fits = {}
    for cand_name, cand in (("luma", luma_zigzag), ("chroma", chroma_zigzag)):
        pairs = [(v, b) for v, b in zip(table, cand) if b >= 16 and v > 1]
        if len(pairs) < 4:
            continue
        scales = sorted(100.0 * v / b for v, b in pairs)
        mid = len(scales) // 2
        s = scales[mid] if len(scales) % 2 else 0.5 * (scales[mid - 1] + scales[mid])
        # libjpeg scale factor: Q >= 50 -> s = 200 - 2Q; Q < 50 -> s = 5000 / Q.
        if s <= 100.0:
            q = (200.0 - s) / 2.0
        else:
            q = 5000.0 / s
        q = max(1.0, min(100.0, q))
        dev = sum(abs(v - min(255.0, max(1.0, b * s / 100.0))) / b for v, b in pairs) / len(pairs)
        fits[cand_name] = {
            "coefficients_used": len(pairs),
            "median_scale_factor": round(s, 2),
            "estimated": round(q, 1),
            "round_to_nearest_5": int(round(q / 5.0) * 5),
            "mean_absolute_deviation_from_table_pct": round(100 * dev, 1),
        }

    if not fits:
        return {"estimated": None, "method": "annex_k_scale_match",
                "note": "no coefficients with base >= 16 and value > 1; "
                        "the table is not an Annex K table we can match"}

    best_name = min(fits, key=lambda k: fits[k]["mean_absolute_deviation_from_table_pct"])
    best = fits[best_name]
    return {
        "estimated": best["estimated"],
        "round_to_nearest_5": best["round_to_nearest_5"],
        "method": f"annex_k_{best_name}_scale_match",
        "table_matched": best_name,
        "coefficients_used": best["coefficients_used"],
        "median_scale_factor": best["median_scale_factor"],
        "mean_absolute_deviation_from_table_pct": best["mean_absolute_deviation_from_table_pct"],
        "plausible_annex_k_scaling": best["mean_absolute_deviation_from_table_pct"] < 15.0,
        "both_candidates": fits,
    }


def parse_exif_ifds(exif_blob: bytes) -> dict[str, Any]:
    """Parse an Exif APP1 payload ("Exif\\0\\0" + TIFF) into IFDs.

    Follows IFD0 plus the Exif, GPS and Interoperability sub-IFDs when present.
    Every field is best effort: an unreadable IFD is reported, not raised.
    """
    out: dict[str, Any] = {
        "exif_blob_bytes": len(exif_blob),
        "byte_order": None,
        "ifds": [],
        "total_tags": 0,
        "tag_names": [],
        "orientation": None,
        "orientation_meaning": None,
        "errors": [],
    }

    if len(exif_blob) < 8:
        out["errors"].append("exif blob shorter than a TIFF header")
        return out

    if exif_blob[:2] == b"II":
        order = "<"
    elif exif_blob[:2] == b"MM":
        order = ">"
    else:
        out["errors"].append("bad TIFF byte order")
        return out
    out["byte_order"] = "little-endian" if order == "<" else "big-endian"

    try:
        magic = struct.unpack_from(order + "H", exif_blob, 2)[0]
        first = struct.unpack_from(order + "I", exif_blob, 4)[0]
    except struct.error as exc:
        out["errors"].append(f"bad TIFF header: {exc}")
        return out
    if magic != 42:
        out["errors"].append(f"TIFF magic {magic} != 42")
        return out

    sub_ifd_names = {0x8769: "ExifIFD", 0x8825: "GPSInfoIFD", 0xA005: "InteroperabilityIFD"}
    pending = [("IFD0", first)]
    seen_ifd_offsets: set[int] = set()
    all_names: list[str] = []

    while pending:
        ifd_name, ifd_off = pending.pop(0)
        if ifd_off in seen_ifd_offsets:
            continue
        seen_ifd_offsets.add(ifd_off)
        if ifd_off + 2 > len(exif_blob):
            out["errors"].append(f"{ifd_name} offset {ifd_off} outside blob")
            continue
        try:
            n_entries = struct.unpack_from(order + "H", exif_blob, ifd_off)[0]
        except struct.error as exc:
            out["errors"].append(f"{ifd_name}: {exc}")
            continue
        if n_entries > 4096:
            out["errors"].append(f"{ifd_name}: implausible entry count {n_entries}")
            n_entries = 0

        ifd = {"name": ifd_name, "offset": ifd_off, "entry_count": n_entries, "tags": []}
        for i in range(n_entries):
            entry_off = ifd_off + 2 + 12 * i
            if entry_off + 12 > len(exif_blob):
                out["errors"].append(f"{ifd_name} entry {i} truncated")
                break
            tag, ftype, cnt = struct.unpack_from(order + "HHI", exif_blob, entry_off)
            raw = exif_blob[entry_off + 8: entry_off + 12]
            name = EXIF_TAG_NAMES.get(tag, f"tag_0x{tag:04X}")
            value: Any = None
            if ftype in EXIF_TYPES:
                vsize = EXIF_TYPES[ftype][1]
                total = vsize * cnt
                if total <= 4:
                    blob = raw[:total]
                else:
                    voff = struct.unpack_from(order + "I", exif_blob, entry_off + 8)[0]
                    if voff + total > len(exif_blob):
                        out["errors"].append(f"{ifd_name} {name}: value offset outside blob")
                        blob = b""
                    else:
                        blob = exif_blob[voff: voff + total]
                try:
                    if ftype == 2:  # ASCII
                        value = blob.split(b"\x00", 1)[0].decode("ascii", "replace")
                    elif ftype in (1, 7):
                        value = list(blob) if cnt else []
                    elif ftype in (3, 4, 9):
                        fmt = {3: "H", 4: "I", 9: "i"}[ftype]
                        value = list(struct.unpack(f"{order}{cnt}{fmt}", blob[:vsize * cnt])) if cnt else []
                    elif ftype in (5, 10):
                        fmt = "II" if ftype == 5 else "ii"
                        pairs = struct.unpack(f"{order}{cnt * 2}{fmt}", blob[:vsize * cnt]) if cnt else []
                        value = [pairs[2 * k] / pairs[2 * k + 1] if pairs[2 * k + 1] else None
                                 for k in range(cnt)] if cnt else []
                    else:
                        value = f"<{EXIF_TYPES[ftype][0]} x{cnt}>"
                except (struct.error, UnicodeDecodeError) as exc:
                    out["errors"].append(f"{ifd_name} {name}: {exc}")
                    value = None

            ifd["tags"].append({
                "tag": f"0x{tag:04X}",
                "name": name,
                "type": EXIF_TYPES[ftype][0] if ftype in EXIF_TYPES else f"type_{ftype}",
                "count": cnt,
                "value": value,
            })
            all_names.append(name)

            if tag in sub_ifd_names and ftype == 4:
                tgt = struct.unpack_from(order + "I", exif_blob, entry_off + 8)[0]
                pending.append((sub_ifd_names[tag], tgt))

            if tag == 0x0112:  # Orientation
                if isinstance(value, list) and value:
                    out["orientation"] = value[0]
                    out["orientation_meaning"] = ORIENTATION_VALUES.get(value[0], "unknown value")

        out["ifds"].append(ifd)

    out["total_tags"] = len(all_names)
    out["tag_names"] = all_names
    return out


def parse_jpeg(data: bytes) -> dict[str, Any]:
    """Walk the JPEG marker structure. Structural facts only, no decoding."""
    out: dict[str, Any] = {
        "is_jpeg": False,
        "bytes": len(data),
        "markers_seen": [],
        "sof": None,
        "progressive": False,
        "components": [],
        "subsampling": None,
        "subsampling_label": None,
        "restart_interval": None,
        "quant_tables": {},
        "quality_estimates": {},
        "app_segments": [],
        "com_segments": [],
        "exif": None,
        "xmp_present": False,
        "icc_profile_present": False,
        "truncated": True,
        "notes": [],
    }

    if len(data) < 2 or data[0] != 0xFF or data[1] != 0xD8:
        out["notes"].append("no SOI (FFD8) at offset 0: not a JPEG file")
        return out
    out["is_jpeg"] = True

    pos = 2
    n = len(data)
    while pos < n:
        if data[pos] != 0xFF:
            out["notes"].append(f"unexpected byte 0x{data[pos]:02X} at offset {pos}")
            break
        marker = data[pos + 1] if pos + 1 < n else 0xFF
        if marker == 0xFF:
            pos += 1
            continue
        if marker == 0xD9:  # EOI
            out["markers_seen"].append("EOI")
            out["truncated"] = False
            pos += 2
            continue
        if marker in STANDALONE:
            out["markers_seen"].append(APP_MARKER_NAMES.get(marker, f"RST{marker & 0x0F:X}" if 0xD0 <= marker <= 0xD7 else f"0x{marker:02X}"))
            pos += 2
            continue
        if pos + 4 > n:
            out["notes"].append("truncated inside a marker length")
            break

        seg_len = _u16(data, pos + 2)
        if seg_len < 2 or pos + 2 + seg_len > n:
            out["notes"].append(f"marker 0x{marker:02X} claims length {seg_len} past end of file")
            break
        payload = data[pos + 4: pos + 2 + seg_len]
        next_pos = pos + 2 + seg_len

        if marker in SOF_MARKERS:
            out["sof"] = SOF_MARKERS[marker]
            out["progressive"] = marker == 0xC2
            if len(payload) >= 6:
                precision = payload[0]
                height = _u16(payload, 1)
                width = _u16(payload, 3)
                ncomp = payload[5]
                out["sof_size"] = {"width": width, "height": height, "precision_bits": precision}
                out["components"] = []
                for c in range(ncomp):
                    o = 6 + 3 * c
                    if o + 3 > len(payload):
                        break
                    cid, hv, tq = payload[o], payload[o + 1], payload[o + 2]
                    out["components"].append({
                        "component_id": cid,
                        "h_sampling": hv >> 4,
                        "v_sampling": hv & 0x0F,
                        "quant_table": tq,
                    })
            out["markers_seen"].append(f"SOF{marker & 0x0F:X}")
        elif marker == 0xDB:  # DQT
            out["markers_seen"].append("DQT")
            off = 0
            while off + 1 <= len(payload) - 1:
                pq_tq = payload[off]
                pq, tq = pq_tq >> 4, pq_tq & 0x0F
                off += 1
                count = 64 if pq == 0 else 128
                if off + count > len(payload):
                    out["notes"].append(f"quant table {tq} truncated inside DQT")
                    break
                if pq == 0:
                    table = list(payload[off:off + 64])
                else:
                    table = list(struct.unpack_from(">64H", payload, off))
                # The segment stores zigzag order; keep both so the quality
                # estimate and any verification use the right one.
                out["quant_tables"][str(tq)] = {
                    "zigzag_order": table,
                    "natural_order": zigzag_to_natural(table),
                    "grid": _table_to_grid(zigzag_to_natural(table)),
                }
                out["quality_estimates"][f"table_{tq}"] = estimate_quality(table)
                off += count
        elif 0xE0 <= marker <= 0xEF:  # APPn
            name = APP_MARKER_NAMES[marker]
            out["markers_seen"].append(name)
            entry = {"marker": name, "payload_bytes": len(payload), "type": None}
            sig = payload[:32]
            if marker == 0xE0 and sig.startswith(b"JFIF\x00"):
                entry["type"] = "JFIF"
                if len(payload) >= 11:
                    entry["version"] = f"{payload[5]}.{payload[6]:02d}"
            elif marker == 0xE0 and sig.startswith(b"JFXX"):
                entry["type"] = "JFXX"
            elif marker == 0xE1 and sig.startswith(b"Exif\x00\x00"):
                entry["type"] = "Exif"
                out["exif"] = parse_exif_ifds(payload[6:])
            elif marker == 0xE1 and sig.startswith(b"http://ns.adobe.com/xap/1.0/\x00"):
                entry["type"] = "XMP"
                out["xmp_present"] = True
            elif marker == 0xE2 and payload.startswith(b"ICC_PROFILE\x00"):
                entry["type"] = "ICC"
                out["icc_profile_present"] = True
            else:
                entry["type"] = "unlabelled"
                entry["first_bytes_hex"] = payload[:16].hex()
            out["app_segments"].append(entry)
        elif marker == 0xFE:  # COM
            out["markers_seen"].append("COM")
            out["com_segments"].append({
                "text": payload.decode("ascii", "replace")[:200],
                "bytes": len(payload),
            })
        elif marker == 0xC4:
            out["markers_seen"].append("DHT")
        elif marker == 0xDD:  # DRI
            out["markers_seen"].append("DRI")
            out["restart_interval"] = _u16(payload, 0)
        elif marker == 0xDA:
            out["markers_seen"].append("SOS")
            out["scan_count"] = out.get("scan_count", 0) + 1
            # Everything after the SOS header is entropy-coded data. Scan it
            # for the next real marker: 0xFF00 is a stuffed byte, and FF D0-D7
            # are restart markers inside the scan.
            i = next_pos
            while i + 1 < n:
                if data[i] == 0xFF and data[i + 1] != 0x00 and not (0xD0 <= data[i + 1] <= 0xD7):
                    break
                i += 1
            if i + 1 < n and data[i] == 0xFF:
                next_pos = i
            else:
                out["notes"].append("no marker found after the scan data")
                next_pos = n
        else:
            out["markers_seen"].append(f"0x{marker:02X}")

        pos = next_pos

    # Subsampling label from the first component, which is the luma component
    # in the YCbCr ordering every phone encoder uses.
    if out["components"]:
        first = out["components"][0]
        hv = (first["h_sampling"], first["v_sampling"])
        out["subsampling"] = {f"component_{c['component_id']}": f"{c['h_sampling']}x{c['v_sampling']}"
                              for c in out["components"]}
        if len(out["components"]) == 1:
            out["subsampling_label"] = "4:4:4 (single component, grayscale)"
        else:
            out["subsampling_label"] = SAMPLING_LABELS.get(hv, f"luma {hv[0]}x{hv[1]} (non-standard naming)")
    return out
