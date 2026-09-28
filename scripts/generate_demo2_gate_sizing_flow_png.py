#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


W, H = 2400, 980
BG = (255, 255, 255)
BOX = (237, 242, 255)
DQN_BG = (232, 248, 240)
BORDER = (40, 40, 40)
TEXT = (20, 20, 20)
ARROW = (30, 30, 30)


def draw_box(draw, xy, text, fill=BOX, radius=20, font=None):
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=BORDER, width=3)

    max_width = x2 - x1 - 24
    words = text.split()
    lines = []
    cur = ""
    for w in words:
        cand = (cur + " " + w).strip()
        l, t, r, b = draw.textbbox((0, 0), cand, font=font)
        if r - l <= max_width or not cur:
            cur = cand
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)

    heights = []
    widths = []
    for line in lines:
        l, t, r, b = draw.textbbox((0, 0), line, font=font)
        widths.append(r - l)
        heights.append(b - t)
    total_h = sum(heights) + max(0, len(lines) - 1) * 4
    y = y1 + (y2 - y1 - total_h) // 2
    for line, lw, lh in zip(lines, widths, heights):
        x = x1 + (x2 - x1 - lw) // 2
        draw.text((x, y), line, fill=TEXT, font=font)
        y += lh + 4


def arrow(draw, p1, p2, width=4):
    draw.line([p1, p2], fill=ARROW, width=width)
    x1, y1 = p1
    x2, y2 = p2
    if abs(x2 - x1) >= abs(y2 - y1):
        sign = 1 if x2 > x1 else -1
        draw.polygon([(x2, y2), (x2 - 16 * sign, y2 - 8), (x2 - 16 * sign, y2 + 8)], fill=ARROW)
    else:
        sign = 1 if y2 > y1 else -1
        draw.polygon([(x2, y2), (x2 - 8, y2 - 16 * sign), (x2 + 8, y2 - 16 * sign)], fill=ARROW)


def main():
    repo_root = Path(__file__).resolve().parents[1]
    out = repo_root / "docs" / "demo2_gate_sizing_flow.png"
    out.parent.mkdir(parents=True, exist_ok=True)

    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    font = ImageFont.load_default()

    y, h = 90, 110
    x0, gap, bw = 40, 30, 250
    labels = [
        "Load OpenROAD design",
        "ERC fix (repair_design / DRV repair)",
        "Buffering",
        "Detailed placement (DP)",
    ]

    boxes = []
    x = x0
    for label in labels:
        box = (x, y, x + bw, y + h)
        boxes.append(box)
        draw_box(draw, box, label, font=font)
        x += bw + gap

    dqn_box = (x + 10, 40, x + 10 + 920, 360)
    draw_box(draw, dqn_box, "DQN sizing flow", fill=DQN_BG, radius=24, font=font)

    inner_y, inner_h = 150, 90
    inner_x, inner_w, inner_gap = dqn_box[0] + 30, 150, 20
    inner_labels = [
        "Build graph/features",
        "Initialize DQN",
        "Identify critical path",
        "Select gate-sizing action",
        "Update circuit and timing",
    ]
    inner_boxes = []
    for i, label in enumerate(inner_labels):
        bx = inner_x + i * (inner_w + inner_gap)
        ib = (bx, inner_y, bx + inner_w, inner_y + inner_h)
        inner_boxes.append(ib)
        draw_box(draw, ib, label, fill=(247, 255, 251), radius=14, font=font)

    post_labels = [
        "Detailed placement (DP)",
        "Timing/routing evaluation",
        "Write DEF and Verilog",
    ]
    post_boxes = []
    px = dqn_box[2] + 40
    for label in post_labels:
        pb = (px, y, px + bw, y + h)
        post_boxes.append(pb)
        draw_box(draw, pb, label, font=font)
        px += bw + gap

    # Main flow arrows
    for i in range(len(boxes) - 1):
        b1 = boxes[i]
        b2 = boxes[i + 1]
        arrow(draw, (b1[2], (b1[1] + b1[3]) // 2), (b2[0], (b2[1] + b2[3]) // 2))

    arrow(
        draw,
        (boxes[-1][2], (boxes[-1][1] + boxes[-1][3]) // 2),
        (dqn_box[0], (boxes[-1][1] + boxes[-1][3]) // 2),
    )
    arrow(
        draw,
        (dqn_box[2], (boxes[-1][1] + boxes[-1][3]) // 2),
        (post_boxes[0][0], (post_boxes[0][1] + post_boxes[0][3]) // 2),
    )

    for i in range(len(post_boxes) - 1):
        b1 = post_boxes[i]
        b2 = post_boxes[i + 1]
        arrow(draw, (b1[2], (b1[1] + b1[3]) // 2), (b2[0], (b2[1] + b2[3]) // 2))

    # DQN inner flow arrows
    for i in range(len(inner_boxes) - 1):
        b1 = inner_boxes[i]
        b2 = inner_boxes[i + 1]
        arrow(draw, (b1[2], (b1[1] + b1[3]) // 2), (b2[0], (b2[1] + b2[3]) // 2), width=3)

    # Loop back: update -> identify critical path
    start = (inner_boxes[-1][2] - 20, inner_boxes[-1][1] + inner_h + 6)
    p2 = (inner_boxes[-1][2] - 20, dqn_box[3] - 35)
    p3 = (inner_boxes[2][0] + 20, dqn_box[3] - 35)
    p4 = (inner_boxes[2][0] + 20, inner_boxes[2][1] + inner_h)
    draw.line([start, p2, p3], fill=ARROW, width=3)
    arrow(draw, p3, p4, width=3)
    draw.text((p3[0] + 10, p3[1] - 25), "repeat until training complete", fill=TEXT, font=font)

    img.save(out, format="PNG")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
