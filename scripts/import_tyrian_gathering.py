#!/usr/bin/env python3
"""Convert the CC0 Tyrian Gathering Marker Project's TacO XML into app data."""

import argparse
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET


def words(value: str) -> str:
    value = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", value)
    return value.replace("_", " ").strip().title()


def marker_name(marker_type: str) -> str:
    parts = marker_type.lower().split(".")
    material = words(parts[-1])
    if "ore" in parts:
        return f"{'Rich ' if 'rich' in parts else ''}{material} Vein"
    if "wood" in parts:
        return f"{material} Wood Node"
    return material


def category(marker_type: str) -> str:
    lowered = marker_type.lower()
    if ".ore." in lowered or lowered.startswith("resourcenode.ore"):
        return "ore"
    if ".wood." in lowered or lowered.startswith("resourcenode.wood"):
        return "wood"
    if ".plant." in lowered or lowered.startswith("resourcenode.plant"):
        return "plant"
    return "other"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()

    markers = []
    for xml_path in sorted(args.source.glob("TGMP_[0-9]*.xml")):
        root = ET.parse(xml_path).getroot()
        for index, poi in enumerate(root.findall(".//POIs/POI")):
            attributes = {key.lower(): value for key, value in poi.attrib.items()}
            marker_type = attributes.get("type", "other")
            guid = attributes.get("guid")
            stable = guid.rstrip("=").replace("/", "_").replace("+", "-") if guid else f"{xml_path.stem}-{index}"
            markers.append({
                "id": f"tgmp-{stable}",
                "mapId": int(attributes["mapid"]),
                "worldX": float(attributes["xpos"]),
                "worldZ": float(attributes["zpos"]),
                "category": category(marker_type),
                "name": marker_name(marker_type),
                "reliability": "possible",
                "source": "Tyrian Gathering Marker Project",
                "notes": "Possible spawn location; presence varies by map instance and daily node placement."
            })

    document = {
        "version": 1,
        "sourceURL": "https://github.com/kriana/Tyrian-Gathering-Marker-Project",
        "sourceRevision": args.revision,
        "license": "CC0-1.0",
        "coveredMapIds": sorted({marker["mapId"] for marker in markers}),
        "markers": markers,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, separators=(",", ":")), encoding="utf-8")


if __name__ == "__main__":
    main()
