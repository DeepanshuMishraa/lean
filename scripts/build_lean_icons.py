#!/usr/bin/env python3
"""
Lean Icons Generator
Creates custom, super minimal, high quality 'fill' SVG icons for the Lean Browser.
"""

import os
import re
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load_icons():
    svg_dir = os.path.join(ROOT, "icons/svg")
    icons = {}
    for fname in sorted(os.listdir(svg_dir)):
        if fname.endswith(".svg"):
            name = fname[:-4]
            with open(os.path.join(svg_dir, fname), "r") as f:
                icons[name] = f.read().strip()
    return icons

ICONS = load_icons()

def validate_all():
    print(f"Validating {len(ICONS)} icons...")
    for name, svg in ICONS.items():
        try:
            root = ET.fromstring(svg)
            assert root.tag.endswith("svg"), f"{name} root is not svg"
            assert root.attrib.get("viewBox") == "0 0 24 24", f"{name} missing 0 0 24 24 viewBox"
        except Exception as e:
            print(f"Error in {name}: {e}")
            raise e
    print("All icons successfully validated as valid SVG XML!")

def generate_swift_file():
    swift_path = os.path.join(ROOT, "Lean/LeanIcons.swift")
    cases = sorted(ICONS.keys())

    swift_code = [
        "//",
        "//  LeanIcons.swift",
        "//  Lean",
        "//",
        "//  Custom high-quality fill SVG icons designed for the Lean Browser UI.",
        "//  Resolution-independent vector silhouettes with zero external dependencies.",
        "//",
        "",
        "import AppKit",
        "import SwiftUI",
        "",
        "public enum LeanIcon: String, CaseIterable, Identifiable, Hashable, Codable {",
    ]

    for c in cases:
        if c == "extension":
            swift_code.append('    case `extension` = "extension"')
        else:
            swift_code.append(f"    case {c}")

    swift_code.extend([
        "",
        "    public static let puzzlePiece: LeanIcon = .extension",
        "    public static let extensionIcon: LeanIcon = .extension",
        "    public static let speaker: LeanIcon = .speakerHigh",
        "    public static let speakerMute: LeanIcon = .speakerSlash",
        "    public static let mute: LeanIcon = .speakerSlash",
        "    public static let split: LeanIcon = .columns",
        "",
        "    public var id: String { rawValue }",
        "",
        "    private static let imageCache = NSCache<NSString, NSImage>()",
        "",
        "    /// High-performance AppKit template vector image, cached per icon.",
        "    public var nsImage: NSImage {",
        "        let key = rawValue as NSString",
        "        if let cached = Self.imageCache.object(forKey: key) {",
        "            return cached",
        "        }",
        "        guard let data = svgString.data(using: .utf8),",
        "              let image = NSImage(data: data) else {",
        "            NSLog(\"Failed to decode Lean icon: %@\", rawValue)",
        "            let fallback = NSImage(systemSymbolName: \"questionmark.square\", accessibilityDescription: rawValue)",
        "                ?? NSImage(size: NSSize(width: 24, height: 24))",
        "            fallback.size = NSSize(width: 24, height: 24)",
        "            fallback.isTemplate = true",
        "            Self.imageCache.setObject(fallback, forKey: key)",
        "            return fallback",
        "        }",
        "        image.size = NSSize(width: 24, height: 24)",
        "        image.isTemplate = true",
        "        Self.imageCache.setObject(image, forKey: key)",
        "        return image",
        "    }",
        "",
        "    /// Crisp resizable SwiftUI Image view conforming to foreground tinting.",
        "    public var fill: Image {",
        "        Image(nsImage: nsImage)",
        "            .interpolation(.high)",
        "            .resizable()",
        "    }",
        "",
        "    /// Solid fill weight icon variant.",
        "    public var bold: Image {",
        "        fill",
        "    }",
        "",
        "    /// Standard UI icon.",
        "    public var uiIcon: Image {",
        "        fill",
        "    }",
        "",
        "    /// Underlying SVG source string.",
        "    public var svgString: String {",
        "        Self.svg(for: self)",
        "    }",
        "",
        "    public static func svg(for icon: LeanIcon) -> String {",
        "        switch icon {",
    ])

    for c in cases:
        escaped_svg = ICONS[c].replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
        swift_code.append(f'        case .{c}:')
        swift_code.append(f'            return "{escaped_svg}"')

    swift_code.extend([
        "        }",
        "    }",
        "}",
        ""
    ])

    with open(swift_path, "w") as f:
        f.write("\n".join(swift_code))
    print(f"Generated Swift icons file at {swift_path}")

def generate_react_file():
    react_path = os.path.join(ROOT, "marketing/src/icons/index.tsx")
    os.makedirs(os.path.dirname(react_path), exist_ok=True)

    lines = [
        "//",
        "// Custom Lean Browser high-quality fill SVG icon components.",
        "//",
        "import React from 'react'",
        "",
        "export interface IconProps extends React.SVGProps<SVGSVGElement> {",
        "  size?: number | string",
        "  weight?: string",
        "}",
        ""
    ]

    for name, svg in sorted(ICONS.items()):
        # Convert camelCase to PascalCase for component name
        pascal_name = name[:1].upper() + name[1:]
        # Extract inner SVG elements (remove <svg ...> and </svg>)
        inner = re.sub(r'^\s*<svg[^>]*>\s*', '', svg, flags=re.MULTILINE)
        inner = re.sub(r'\s*</svg>\s*$', '', inner, flags=re.MULTILINE).strip()
        # Convert fill-rule, clip-rule, stroke-width, stroke-linecap, stroke-linejoin to JSX camelCase
        jsx_inner = inner.replace('fill-rule=', 'fillRule=').replace('clip-rule=', 'clipRule=')
        jsx_inner = jsx_inner.replace('stroke-width=', 'strokeWidth=').replace('stroke-linecap=', 'strokeLinecap=').replace('stroke-linejoin=', 'strokeLinejoin=')

        lines.append(f"export const {pascal_name}: React.FC<IconProps> = ({{")
        lines.append(f"  size = 24,")
        lines.append(f"  className,")
        lines.append(f"  ...props")
        lines.append(f"}}) => (")
        lines.append(f"  <svg")
        lines.append(f"    width={{size}}")
        lines.append(f"    height={{size}}")
        lines.append(f"    viewBox=\"0 0 24 24\"")
        lines.append(f"    fill=\"currentColor\"")
        lines.append(f"    className={{className}}")
        lines.append(f"    {{...props}}")
        lines.append(f"  >")
        for l in jsx_inner.split("\n"):
            lines.append(f"    {l}")
        lines.append(f"  </svg>")
        lines.append(f")")
        lines.append("")

    # Also add standard aliases if needed
    lines.append("export const SidebarIcon = Sidebar")
    lines.append("")

    with open(react_path, "w") as f:
        f.write("\n".join(lines))
    print(f"Generated React icons file at {react_path}")

if __name__ == "__main__":
    validate_all()
    generate_swift_file()
    generate_react_file()

