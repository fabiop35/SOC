# -*- coding: utf-8 -*-
"""Genera el diagrama 'Phase 1 - Technical Architecture' del SOC (4 tiers)."""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Circle, Polygon

W, H = 14.08, 7.68
DPI = 200

BG = "#F4F6FA"
PANEL = "#FFFFFF"
PANEL_EDGE = "#DCE3ED"
INK = "#16202E"
MUTED = "#66748A"
CARD = "#FAFBFD"
CARD_EDGE = "#E3E9F2"

T_COLORS = ["#2F6FEB", "#7C3AED", "#E8610C", "#0E9F6E"]
T_TINT = ["#EAF1FE", "#F2ECFE", "#FDF0E6", "#E7F7F1"]

fig = plt.figure(figsize=(W, H), dpi=DPI)
ax = fig.add_axes([0, 0, 1, 1])
ax.set_xlim(0, W)
ax.set_ylim(0, H)
ax.axis("off")
ax.set_facecolor(BG)

_cache = {}


def measure(s, size, weight="normal", family="DejaVu Sans"):
    key = (s, size, weight, family)
    if key in _cache:
        return _cache[key]
    t = ax.text(0, 0, s, fontsize=size, fontweight=weight, fontfamily=family, alpha=0)
    fig.canvas.draw()
    bb = t.get_window_extent(renderer=fig.canvas.get_renderer())
    t.remove()
    w = bb.width / fig.dpi
    _cache[key] = w
    return w


def rrect(x, y, w, h, fc, ec=None, lw=1.0, r=0.10, z=2, alpha=1.0):
    ax.add_patch(FancyBboxPatch(
        (x, y), w, h,
        boxstyle="round,pad=0,rounding_size=%.3f" % r,
        facecolor=fc, edgecolor=ec if ec else "none",
        linewidth=lw if ec else 0, zorder=z, alpha=alpha))


def wrap(s, size, max_w, weight="normal", family="DejaVu Sans"):
    lines, cur = [], ""
    for w in s.split():
        t = (cur + " " + w).strip()
        if cur and measure(t, size, weight, family) > max_w:
            lines.append(cur)
            cur = w
        else:
            cur = t
    if cur:
        lines.append(cur)
    return lines


def arrow_down(x, y_from, y_to, color, head=0.07, lw=2.0):
    ax.plot([x, x], [y_from, y_to + head], color=color, lw=lw, solid_capstyle="round", zorder=6)
    ax.add_patch(Polygon([[x - head * 0.6, y_to + head], [x + head * 0.6, y_to + head], [x, y_to]],
                         closed=True, facecolor=color, edgecolor="none", zorder=6))


def arrow_left(x_from, x_to, y, color, head=0.07, lw=1.8):
    ax.plot([x_from, x_to + head], [y, y], color=color, lw=lw, solid_capstyle="round", zorder=6)
    ax.add_patch(Polygon([[x_to + head, y + head * 0.6], [x_to + head, y - head * 0.6], [x_to, y]],
                         closed=True, facecolor=color, edgecolor="none", zorder=6))


# ---------------------------------------------------------------- header
ax.text(0.55, 7.15, "SOC  —  Phase 1: Technical Architecture", fontsize=25, weight="bold",
        color=INK, va="center")
ax.text(0.57, 6.84, "Telemetry  →  Detection  →  Automation  →  Investigation & CTI",
        fontsize=11.5, color=MUTED, va="center")
ax.text(13.55, 7.15, "4-TIER DETECTION & RESPONSE STACK", fontsize=9.5, weight="bold",
        color=MUTED, va="center", ha="right")
ax.text(13.55, 6.84,
        "Sysmon / auditd  ·  Zeek  ·  Suricata  ·  Wazuh  ·  OpenSearch  ·  Shuffle  ·  TheHive  ·  MISP",
        fontsize=9.5, color=MUTED, va="center", ha="right")
ax.plot([0.55, 13.55], [6.60, 6.60], color=PANEL_EDGE, lw=1.4, zorder=1)

# ---------------------------------------------------------------- content
TIERS = [
    {
        "name": "Telemetry & Ingestion",
        "sub": "Host, protocol and network log collection",
        "cards": [
            ("Command-Line Auditing", [
                ("Sysmon Event IDs 1 / 3 / 6 / 22", "mono"),
                ("Event 4688 (Windows process creation)", "normal"),
                ("Linux auditd rules", "normal"),
            ]),
            ("Zeek Protocol Metadata", [
                ("dns.log", "mono"),
                ("ssl.log", "mono"),
                ("conn.log", "mono"),
            ]),
            ("Suricata NIDS", [
                ("Signature-based alerts", "normal"),
                ("Protocol anomaly detection", "normal"),
                ("Flow & session metadata", "normal"),
            ]),
        ],
    },
    {
        "name": "SIEM & Analytics",
        "sub": "Parsing, correlation and time-series storage",
        "cards": [
            ("Wazuh Manager", [
                ("Log parsing & normalization", "normal"),
                ("Server-side rules & alerts", "normal"),
            ]),
            ("MITRE ATT&CK", [
                ("Rule correlation", "normal"),
                ("Technique & tactic mapping", "normal"),
            ]),
            ("Sigma", [
                ("Rule compilation", "normal"),
                ("Generic detection logic", "normal"),
            ]),
            ("OpenSearch", [
                ("Time-series log indexing", "normal"),
                ("Dashboards & hunting queries", "normal"),
            ]),
        ],
    },
    {
        "name": "SOAR & Automation",
        "sub": "Enrichment and response playbooks",
        "cards": [
            ("Shuffle", [
                ("Workflow orchestration", "normal"),
                ("Event-triggered playbooks", "normal"),
            ]),
            ("Threat Enrichment", [
                ("File hash reputation lookup", "normal"),
                ("VirusTotal / MISP", "normal"),
            ]),
            ("Active Response", [
                ("Endpoint network isolation", "normal"),
                ("Triggered on critical events", "normal"),
            ]),
        ],
    },
    {
        "name": "Case Management & CTI",
        "sub": "Investigation workflow and threat intelligence",
        "cards": [
            ("TheHive 5.x", [
                ("PICERL investigation templates", "normal"),
                ("Task, evidence & timeline", "normal"),
            ]),
            ("Forensics", [
                ("Chain-of-custody records", "normal"),
                ("Evidence integrity logging", "normal"),
            ]),
            ("MISP", [
                ("STIX / TAXII feed sync", "normal"),
                ("Indicator sharing & pivoting", "normal"),
            ]),
        ],
    },
]

PX0, PX1 = 0.55, 12.95
BADGE_X = 0.92
STRIP = 0.30
PANEL_H = 1.37
GAP = 0.31
CARD_H = 0.95
CX0, CX1 = 0.80, 12.80

tops = []
y = 6.48
for _ in range(4):
    tops.append(y)
    y -= PANEL_H + GAP
panels = [(t - PANEL_H, t) for t in tops]

for i, (tier, (py0, py1)) in enumerate(zip(TIERS, panels)):
    col, tint = T_COLORS[i], T_TINT[i]

    rrect(PX0 + 0.03, py0 - 0.05, PX1 - PX0, PANEL_H, "#000000", r=0.12, z=1, alpha=0.05)
    rrect(PX0, py0, PX1 - PX0, PANEL_H, PANEL, PANEL_EDGE, lw=1.2, r=0.12, z=2)
    rrect(PX0, py0, 0.075, PANEL_H, col, r=0.12, z=3)

    # header strip: badge + tier number + name (left), subtitle (right)
    sy = py1 - STRIP / 2
    ax.add_patch(Circle((BADGE_X, sy), 0.135, facecolor=tint, edgecolor=col, lw=1.3, zorder=4))
    ax.text(BADGE_X, sy - 0.005, str(i + 1), fontsize=11, weight="bold", color=col,
            ha="center", va="center", zorder=5)
    ax.text(BADGE_X + 0.26, sy, "TIER %d" % (i + 1), fontsize=9.5, weight="bold", color=col,
            va="center", zorder=5)
    nx = BADGE_X + 0.26 + measure("TIER %d" % (i + 1), 9.5, "bold") + 0.20
    ax.text(nx, sy - 0.01, tier["name"], fontsize=15, weight="bold", color=INK, va="center", zorder=5)
    ax.text(PX1 - 0.22, sy, tier["sub"], fontsize=8.8, color=MUTED, va="center", ha="right", zorder=5)
    ax.plot([PX0 + 0.16, PX1 - 0.16], [py1 - STRIP, py1 - STRIP], color=PANEL_EDGE, lw=1.0, zorder=3)

    n = len(tier["cards"])
    gap = 0.20
    cw = (CX1 - CX0 - gap * (n - 1)) / n
    cy0 = py0 + 0.04

    for j, (ctitle, items) in enumerate(tier["cards"]):
        cx = CX0 + j * (cw + gap)
        rrect(cx, cy0, cw, CARD_H, CARD, CARD_EDGE, lw=1.0, r=0.08, z=3)
        rrect(cx, cy0, 0.055, CARD_H, col, r=0.03, z=4)
        tx = cx + 0.17
        top = cy0 + CARD_H
        ax.text(tx, top - 0.215, ctitle, fontsize=10.4, weight="bold", color=INK,
                va="center", ha="left", zorder=5)

        max_w = cw - 0.36
        blocks = []
        for text, style in items:
            fam = "DejaVu Sans Mono" if style == "mono" else "DejaVu Sans"
            blocks.append((wrap(text, 8.2, max_w, "normal", fam), fam))
        nlines = sum(len(b[0]) for b in blocks)
        avail = CARD_H - 0.44
        lh = min(0.155, (avail - 0.03 * (len(blocks) - 1)) / max(nlines, 1))
        fs = min(8.2, lh / 0.0215)

        yy = top - 0.42
        for lines, fam in blocks:
            for k, ln in enumerate(lines):
                if k == 0:
                    ax.add_patch(Circle((tx + 0.045, yy + 0.006), 0.030, facecolor=col,
                                        edgecolor="none", zorder=5))
                ax.text(tx + 0.15, yy, ln, fontsize=fs, color="#334155", va="center",
                        ha="left", fontfamily=fam, zorder=5)
                if measure(ln, fs, "normal", fam) > max_w:
                    print("WARN overflow:", repr(ln))
                yy -= lh
            yy -= 0.03

# ---------------------------------------------------------------- flow arrows
flows = [
    (0, "Syslog  ·  Suricata alerts  ·  Zeek metadata  →  Wazuh ingestion"),
    (1, "Correlated alerts  (ATT&CK techniques  ·  Sigma matches)"),
    (2, "Enrichment results  ·  network isolation  ·  investigation cases"),
]
for idx, label in flows:
    y_from = panels[idx][0] + 0.02
    y_to = panels[idx + 1][1] - 0.02
    arrow_down(BADGE_X, y_from, y_to, "#9AA7BA")
    ax.text(BADGE_X + 0.24, (y_from + y_to) / 2, label, fontsize=8.6, color=MUTED,
            va="center", ha="left", zorder=6)

# ---------------------------------------------------------------- CTI feedback loop
arrow_left(PX1, PX1 + 0.06, panels[3][0] + 0.26, T_COLORS[3])
ax.plot([PX1 + 0.30, PX1 + 0.30], [panels[3][0] + 0.26, panels[0][1] - 0.26],
        color=T_COLORS[3], lw=1.8, zorder=6)
arrow_left(PX1 + 0.36, PX1 + 0.06, panels[0][1] - 0.26, T_COLORS[3])
ax.text(PX1 + 0.48, (panels[0][1] + panels[3][0]) / 2, "CTI feedback loop  ·  STIX / TAXII",
        fontsize=8.8, color=T_COLORS[3], va="center", ha="center", rotation=90,
        weight="bold", zorder=6)

fig.savefig("images/arquitectura_fases.jpg", dpi=DPI, facecolor=BG, pil_kwargs={"quality": 95})
fig.savefig("images/arquitectura_fases.png", dpi=DPI, facecolor=BG)
print("wrote images/arquitectura_fases.jpg / .png")
