#!/usr/bin/env python3
"""
像素小人年龄可视化 - Pixel Character Age Visualizer
显示从婴儿到老人的像素小人 / Displays pixel characters from baby to elder
"""

import sys
import time
import os

# ANSI color codes
class Color:
    RESET   = "\033[0m"
    BOLD    = "\033[1m"
    # Foreground
    BLACK   = "\033[30m"
    RED     = "\033[31m"
    GREEN   = "\033[32m"
    YELLOW  = "\033[33m"
    BLUE    = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN    = "\033[36m"
    WHITE   = "\033[37m"
    BRIGHT_BLACK   = "\033[90m"
    BRIGHT_RED     = "\033[91m"
    BRIGHT_GREEN   = "\033[92m"
    BRIGHT_YELLOW  = "\033[93m"
    BRIGHT_BLUE    = "\033[94m"
    BRIGHT_MAGENTA = "\033[95m"
    BRIGHT_CYAN    = "\033[96m"
    BRIGHT_WHITE   = "\033[97m"

# Pixel block
PX = "██"
SP = "  "

def colorize(text, color):
    return f"{color}{text}{Color.RESET}"

# ──────────────────────────────────────────────
#  Pixel art definitions (each row = list of bool)
#  True = filled pixel, False = space
# ──────────────────────────────────────────────

# Baby (0-2) — small, round head, no neck, tiny body
BABY = [
    " OOO ",
    "OOOOO",
    "O ^ O",
    " OOO ",
    " TTT ",
    "TTTTT",
    " T T ",
    "  .  ",
]

# Child (3-12) — bigger head, short body
CHILD = [
    " OOO ",
    "OOOOO",
    "O o O",
    "OvvvO",
    " OOO ",
    " BBB ",
    "BBBBB",
    " B B ",
    " B B ",
]

# Teen (13-19) — taller, styled hair
TEEN = [
    " ~HHH~",
    "HHHHHH",
    "H o oH",
    "H ^ H",
    " HHHH ",
    " SSSS ",
    "SSSSSS",
    " S  S ",
    " SS SS",
    " S  S ",
]

# Young Adult (20-35) — confident posture, arms out
YOUNG_ADULT = [
    "  OOO  ",
    " OOOOO ",
    " O o O ",
    " OOOOO ",
    "  OOO  ",
    "SSSSSSS",
    " SSSSS ",
    "  S S  ",
    "  S S  ",
    " SS SS ",
]

# Middle-aged (36-55) — slightly wider body
MIDDLE_AGED = [
    "  OOO  ",
    " OOOOO ",
    " Oo oO ",
    " O..O  ",
    " OOOOO ",
    " SSSSS ",
    "SSSSSSS",
    "  S S  ",
    "  S S  ",
    " SS SS ",
]

# Elder (56-70) — hunched, cane
ELDER = [
    " OOO  ",
    "OOOOO ",
    "Oo oO ",
    "O~~~~O",
    " OOOO ",
    " SSS  ",
    "SSSSS|",
    " S S  |",
    " S S  |",
    " S S  .",
]

# Very Elder (71+) — more hunched, shorter
VERY_ELDER = [
    " OOO ",
    "OOOOO",
    "Oo~oO",
    "OOOOO",
    " ~OOO~",
    " SSS |",
    "SSSS |",
    " S S .",
    " S   ",
]


# ──────────────────────────────────────────────
#  Rendered pixel art using block characters
# ──────────────────────────────────────────────

def make_pixel_art(template, fg_color, bg_fill="  "):
    """Convert template strings into colored block art."""
    lines = []
    for row in template:
        line = ""
        for ch in row:
            if ch in "O":   # head / skin
                line += colorize("██", Color.BRIGHT_YELLOW)
            elif ch in "H": # hair
                line += colorize("██", Color.BRIGHT_BLACK)
            elif ch in "~": # wrinkles / detail
                line += colorize("▓▓", Color.YELLOW)
            elif ch in "S": # shirt / body
                line += colorize("██", fg_color)
            elif ch in "T": # baby body
                line += colorize("██", Color.BRIGHT_CYAN)
            elif ch in "B": # child body
                line += colorize("██", Color.BRIGHT_GREEN)
            elif ch in "o": # eyes
                line += colorize("◉◉", Color.BRIGHT_BLACK)
            elif ch in "^": # nose/smile
                line += colorize("▲ ", Color.BRIGHT_RED)
            elif ch in "v": # cheeks
                line += colorize("♥ ", Color.RED)
            elif ch in ".": # feet / cane tip
                line += colorize("▄▄", Color.BRIGHT_BLACK)
            elif ch in "|": # cane shaft
                line += colorize(" |", Color.BRIGHT_BLACK)
            elif ch in "~":
                line += colorize("~~", Color.WHITE)
            elif ch == " ":
                line += "  "
            else:
                line += "  "
        lines.append(line)
    return lines


# ──────────────────────────────────────────────
#  Age stage definitions
# ──────────────────────────────────────────────

STAGES = [
    {
        "label": "Baby",
        "age_range": "0-2",
        "color": Color.BRIGHT_CYAN,
        "template": [
            [0,0,1,1,1,0,0],
            [0,1,1,1,1,1,0],
            [1,1,0,1,0,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [0,0,1,1,1,0,0],
            [0,1,1,1,1,1,0],
            [0,0,1,0,1,0,0],
        ],
        "skin": Color.BRIGHT_YELLOW,
        "body": Color.BRIGHT_CYAN,
        "hair": Color.BRIGHT_YELLOW,
        "eyes": "  ",
        "description": "👶 婴儿 / Baby",
    },
    {
        "label": "Child",
        "age_range": "3-12",
        "color": Color.BRIGHT_GREEN,
        "template": None,
        "description": "🧒 儿童 / Child",
    },
    {
        "label": "Teen",
        "age_range": "13-19",
        "color": Color.BRIGHT_BLUE,
        "description": "🧑 青少年 / Teen",
    },
    {
        "label": "Young Adult",
        "age_range": "20-35",
        "color": Color.BRIGHT_MAGENTA,
        "description": "👨 青年 / Young Adult",
    },
    {
        "label": "Middle-aged",
        "age_range": "36-55",
        "color": Color.YELLOW,
        "description": "🧔 中年 / Middle-aged",
    },
    {
        "label": "Elder",
        "age_range": "56-70",
        "color": Color.BRIGHT_BLACK,
        "description": "👴 老年 / Elder",
    },
    {
        "label": "Very Elder",
        "age_range": "71+",
        "color": Color.WHITE,
        "description": "🧓 高龄 / Very Elder",
    },
]


# ──────────────────────────────────────────────
#  Block-pixel renderer (proper grid approach)
# ──────────────────────────────────────────────

SKIN   = Color.BRIGHT_YELLOW
HAIR_DARK = Color.BRIGHT_BLACK
HAIR_GRAY = "\033[37m"
SHIRT_COLORS = [
    Color.BRIGHT_CYAN,    # baby
    Color.BRIGHT_GREEN,   # child
    Color.BRIGHT_BLUE,    # teen
    Color.BRIGHT_MAGENTA, # young adult
    Color.YELLOW,         # middle aged
    "\033[33m",           # elder (dark yellow)
    Color.WHITE,          # very elder
]

# Grid: 0=space, 1=skin, 2=hair, 3=shirt, 4=pants, 5=eye, 6=cane, 7=wrinkle
CHARACTERS = {
    "baby": {
        "grid": [
            [0,0,1,1,1,0,0],
            [0,1,1,1,1,1,0],
            [1,1,5,1,5,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [0,0,3,3,3,0,0],
            [0,3,3,3,3,3,0],
            [0,0,4,0,4,0,0],
        ],
        "shirt_idx": 0,
        "hair_color": SKIN,
        "label": "👶 Baby",
        "age": "Age: 0–2",
    },
    "child": {
        "grid": [
            [0,0,2,2,2,0,0],
            [0,2,1,1,1,2,0],
            [0,1,1,5,1,1,0],  # wider head
            [0,1,1,1,1,1,0],
            [0,0,1,1,1,0,0],
            [0,0,3,3,3,0,0],
            [0,3,3,3,3,3,0],
            [0,3,3,0,3,3,0],
            [0,0,4,0,4,0,0],
            [0,0,4,0,4,0,0],
        ],
        "shirt_idx": 1,
        "hair_color": HAIR_DARK,
        "label": "🧒 Child",
        "age": "Age: 3–12",
    },
    "teen": {
        "grid": [
            [0,2,2,2,2,0,0],
            [0,2,1,1,1,2,0],
            [0,1,1,5,1,1,0],
            [0,1,0,1,0,1,0],  # smile gap
            [0,0,1,1,1,0,0],
            [3,3,3,3,3,3,3],
            [0,3,3,3,3,3,0],
            [0,3,3,0,3,3,0],
            [0,0,4,0,4,0,0],
            [0,0,4,0,4,0,0],
            [0,4,4,0,4,4,0],
        ],
        "shirt_idx": 2,
        "hair_color": HAIR_DARK,
        "label": "🧑 Teen",
        "age": "Age: 13–19",
    },
    "young_adult": {
        "grid": [
            [0,0,2,2,2,0,0],
            [0,1,1,1,1,1,0],
            [0,1,5,1,5,1,0],
            [0,1,1,1,1,1,0],
            [0,0,1,1,1,0,0],
            [3,3,3,3,3,3,3],
            [0,3,3,3,3,3,0],
            [0,3,0,0,0,3,0],
            [0,0,4,0,4,0,0],
            [0,0,4,0,4,0,0],
            [0,4,4,0,4,4,0],
        ],
        "shirt_idx": 3,
        "hair_color": HAIR_DARK,
        "label": "👨 Young Adult",
        "age": "Age: 20–35",
    },
    "middle_aged": {
        "grid": [
            [0,0,2,2,2,0,0],
            [0,1,1,1,1,1,0],
            [0,1,5,1,5,1,0],
            [0,1,7,1,7,1,0],  # wrinkles
            [0,1,1,1,1,1,0],
            [0,0,1,1,1,0,0],
            [3,3,3,3,3,3,3],
            [3,3,3,3,3,3,3],  # wider body
            [0,0,4,0,4,0,0],
            [0,0,4,0,4,0,0],
            [0,4,4,0,4,4,0],
        ],
        "shirt_idx": 4,
        "hair_color": HAIR_GRAY,
        "label": "🧔 Middle-aged",
        "age": "Age: 36–55",
    },
    "elder": {
        "grid": [
            [0,0,2,2,2,0,0],
            [0,1,1,1,1,1,0],
            [0,1,5,1,5,1,0],
            [0,1,7,7,7,1,0],
            [0,1,1,1,1,1,0],
            [0,0,1,1,1,0,0],
            [0,3,3,3,3,0,6],
            [0,3,3,3,3,0,6],
            [0,0,4,4,0,0,6],
            [0,4,4,4,4,0,6],
            [0,4,0,0,4,0,6],
        ],
        "shirt_idx": 5,
        "hair_color": HAIR_GRAY,
        "label": "👴 Elder",
        "age": "Age: 56–70",
        "hunched": True,
    },
    "very_elder": {
        "grid": [
            [0,0,2,2,0,0,0],
            [0,1,1,1,1,0,0],
            [0,1,5,1,5,0,0],
            [0,1,7,7,1,0,0],
            [0,1,1,1,0,6,0],
            [0,3,3,3,0,6,0],
            [3,3,3,3,0,6,0],
            [0,0,4,4,0,6,0],
            [0,4,4,0,0,6,0],
            [0,4,0,0,0,6,0],
            [0,0,0,0,0,6,0],
        ],
        "shirt_idx": 6,
        "hair_color": Color.WHITE,
        "label": "🧓 Very Elder",
        "age": "Age: 71+",
        "hunched": True,
    },
}

CELL_COLOR = {
    0: None,           # space
    1: SKIN,           # skin
    2: None,           # hair (per-character)
    3: None,           # shirt (per-character)
    4: "\033[34m",     # pants (dark blue)
    5: "\033[30m",     # eyes (black)
    6: "\033[33m",     # cane (brown/yellow)
    7: "\033[33m",     # wrinkle (yellow-ish)
}


# ──────────────────────────────────────────────
#  美国年龄里程碑法律  /  U.S. Age Milestone Laws
#  (age -> list of (law_name, description, emoji))
# ──────────────────────────────────────────────
US_LAWS = {
    0:  [("Birth Registration",      "Social Security Act §205 — SSN issued at birth",          "📜")],
    5:  [("Compulsory Education",    "Every state mandates school enrollment by age 5–6",        "🏫")],
    13: [("COPPA",                   "Children's Online Privacy Protection Act — parental consent required under 13", "🔒")],
    16: [("Driver's License",        "Most states allow driving at 16 (graduated license)",      "🚗"),
         ("Work Permit",             "FLSA permits work with restrictions; full work at 16",     "💼")],
    17: [("R-Rated Films",           "MPAA rating — unaccompanied viewing allowed at 17",        "🎬"),
         ("Military Enlistment",     "Can enlist with parental consent (10 U.S.C. §505)",        "🎖️")],
    18: [("Voting Rights",           "26th Amendment — right to vote",                           "🗳️"),
         ("Legal Adult",             "Age of majority in most states — full contract rights",    "⚖️"),
         ("Federal Tobacco",         "Family Smoking Prevention Act — purchase age raised to 21 (2019)", "🚭"),
         ("Military Service",        "Can enlist without parental consent",                      "🪖"),
         ("Lottery",                 "Most states allow lottery purchase at 18",                 "🎰")],
    21: [("Alcohol",                 "21st Amendment / National Minimum Drinking Age Act 1984",  "🍺"),
         ("Handgun Purchase",        "Federal law prohibits FFL handgun sales under 21",         "🔫"),
         ("Car Rental",              "Most agencies require age 21+ (25 for no surcharge)",      "🚙")],
    25: [("House of Reps",           "U.S. Constitution Art. I §2 — minimum age to serve",       "🏛️"),
         ("Brain Fully Developed",   "CDC/NIH: prefrontal cortex fully matures ~25",             "🧠")],
    30: [("U.S. Senate",             "U.S. Constitution Art. I §3 — minimum age to serve",       "🏛️")],
    35: [("U.S. President",          "U.S. Constitution Art. II §1 — minimum age to serve",      "🇺🇸")],
    59: [("IRA Withdrawal",          "IRS Rule — penalty-free IRA withdrawals at 59½",           "💰")],
    62: [("Early Social Security",   "SSA — early retirement benefits (reduced amount)",         "💵")],
    65: [("Medicare",                "Social Security Act Title XVIII — health coverage begins", "🏥"),
         ("Senior Discounts",        "AARP membership, airline/hotel senior rates widely apply", "🎟️")],
    67: [("Full Social Security",    "SSA — full retirement benefit for those born after 1960",  "💰")],
    70: [("Max Social Security",     "SSA — delayed credits max out; no benefit to wait longer", "💎")],
    100:[("Centenarian",             "President sends congratulatory letter (White House tradition)", "🎉"),
         ("Supercentenarian path",   "110+ qualifies as supercentenarian per Gerontology Research", "🌟")],
}


def render_character(char_key, width=7):
    """Render a single character as list of colored strings."""
    char = CHARACTERS[char_key]
    grid = char["grid"]
    shirt_color = SHIRT_COLORS[char["shirt_idx"]]
    hair_color = char["hair_color"]
    lines = []
    for row in grid:
        line = ""
        # Pad row to width
        padded = row + [0] * (width - len(row))
        for cell in padded[:width]:
            if cell == 0:
                line += "  "
            elif cell == 1:
                line += colorize("██", SKIN)
            elif cell == 2:
                line += colorize("██", hair_color)
            elif cell == 3:
                line += colorize("██", shirt_color)
            elif cell == 4:
                line += colorize("██", "\033[34m")
            elif cell == 5:
                line += colorize("◉◉", "\033[30m")
            elif cell == 6:
                line += colorize(" |", "\033[33m")
            elif cell == 7:
                line += colorize("~~", "\033[37m")
            else:
                line += "  "
        lines.append(line)
    return lines


def print_all_ages(animated=False):
    """Print all age stage pixel characters side by side in groups."""
    char_keys = list(CHARACTERS.keys())
    try:
        terminal_width = os.get_terminal_size().columns
    except OSError:
        terminal_width = 80

    print()
    print(colorize("  ██████╗ ██╗██╗  ██╗███████╗██╗      ██████╗██╗  ██╗ █████╗ ██████╗  ██████╗ ", Color.BRIGHT_CYAN))
    print(colorize("  ██╔══██╗██║╚██╗██╔╝██╔════╝██║     ██╔════╝██║  ██║██╔══██╗██╔══██╗██╔══██╗", Color.BRIGHT_CYAN))
    print(colorize("  ██████╔╝██║ ╚███╔╝ █████╗  ██║     ██║     ███████║███████║██████╔╝███████║", Color.BRIGHT_CYAN))
    print(colorize("  ██╔═══╝ ██║ ██╔██╗ ██╔══╝  ██║     ██║     ██╔══██║██╔══██║██╔══██╗██╔══██║", Color.BRIGHT_CYAN))
    print(colorize("  ██║     ██║██╔╝ ██╗███████╗███████╗╚██████╗██║  ██║██║  ██║██║  ██║██║  ██║", Color.BRIGHT_CYAN))
    print(colorize("  ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝", Color.BRIGHT_CYAN))
    print()
    print(colorize("           像素小人年龄可视化  ·  Pixel Character Age Visualizer", Color.BRIGHT_WHITE))
    print(colorize("  " + "─" * 70, Color.BRIGHT_BLACK))
    print()

    # Render all characters
    rendered = {}
    for key in char_keys:
        rendered[key] = render_character(key)

    # Max height across all characters
    max_height = max(len(v) for v in rendered.values())

    # Pad all to same height
    for key in char_keys:
        while len(rendered[key]) < max_height:
            rendered[key].append("  " * 7)

    # Group: 4 per row
    GROUP_SIZE = 4
    for g_start in range(0, len(char_keys), GROUP_SIZE):
        group = char_keys[g_start:g_start + GROUP_SIZE]
        char_width = 7  # cells wide

        # Print rows
        for row_idx in range(max_height):
            line = "  "
            for key in group:
                cell_line = rendered[key][row_idx]
                # Each cell = 2 chars wide, 7 cells = 14 chars + color codes
                line += cell_line + "    "
            print(line)
            if animated:
                time.sleep(0.02)

        # Print labels below each character
        label_line = "  "
        age_line = "  "
        for key in group:
            char = CHARACTERS[key]
            label = char["label"]
            age = char["age"]
            # Center within 14 chars (7 cells * 2)
            label_str = label.center(16)
            age_str = age.center(16)
            label_line += colorize(label_str, Color.BRIGHT_WHITE) + "  "
            age_line   += colorize(age_str,   Color.BRIGHT_YELLOW) + "  "
        print(label_line)
        print(age_line)
        print()

    print(colorize("  " + "─" * 70, Color.BRIGHT_BLACK))
    print()
    print(colorize("  Life is a journey through all these stages.", Color.BRIGHT_GREEN))
    print(colorize("  生命是穿越所有这些阶段的旅程。", Color.BRIGHT_GREEN))
    print()


def get_laws_at_age(age: int) -> list:
    """Return all US milestone laws that unlock at or before this age."""
    result = []
    for milestone_age in sorted(US_LAWS.keys()):
        if age >= milestone_age:
            for law in US_LAWS[milestone_age]:
                result.append((milestone_age, *law))
    return result


def get_laws_unlocked_at(age: int) -> list:
    """Return US laws that unlock exactly at this age."""
    # Check exact age and age-1 for half-year milestones (59 covers 59.5)
    result = []
    check = age if age != 59 else 59
    if check in US_LAWS:
        for law in US_LAWS[check]:
            result.append((check, *law))
    return result


def print_us_laws_timeline(animated: bool = True):
    """Print a visual timeline of all US age milestone laws."""
    print()
    print(colorize("  ╔══════════════════════════════════════════════════════════════════╗", Color.BRIGHT_CYAN))
    print(colorize("  ║     🇺🇸  美国年龄里程碑法律  /  U.S. Age Milestone Laws  🇺🇸      ║", Color.BRIGHT_CYAN))
    print(colorize("  ╚══════════════════════════════════════════════════════════════════╝", Color.BRIGHT_CYAN))
    print()

    age_to_key = {
        0: "baby", 5: "baby", 13: "child", 16: "teen", 17: "teen",
        18: "teen", 21: "young_adult", 25: "young_adult", 30: "young_adult",
        35: "young_adult", 59: "middle_aged", 62: "elder", 65: "elder",
        67: "elder", 70: "elder", 100: "very_elder",
    }

    for milestone_age in sorted(US_LAWS.keys()):
        char_key = age_to_key.get(milestone_age, "middle_aged")
        shirt_color = SHIRT_COLORS[CHARACTERS[char_key]["shirt_idx"]]

        age_label = f"Age {milestone_age}" if milestone_age != 59 else "Age 59½"
        print(colorize(f"  {'─'*66}", Color.BRIGHT_BLACK))
        print(colorize(f"  ◆ {age_label}", shirt_color + Color.BOLD))

        for _, name, desc, emoji in [(milestone_age, *l) for l in US_LAWS[milestone_age]]:
            print(f"    {emoji}  {colorize(name, Color.BRIGHT_WHITE)}")
            # Word-wrap description at 58 chars
            words = desc.split()
            line = "       "
            for word in words:
                if len(line) + len(word) + 1 > 66:
                    print(colorize(line, Color.BRIGHT_BLACK))
                    line = "       " + word
                else:
                    line += (" " if line.strip() else "") + word
            if line.strip():
                print(colorize(line, Color.BRIGHT_BLACK))

        if animated:
            time.sleep(0.05)

    print(colorize(f"  {'─'*66}", Color.BRIGHT_BLACK))
    print()
    print(colorize("  Sources: U.S. Constitution · SSA · IRS · FLSA · COPPA · MPAA", Color.BRIGHT_BLACK))
    print()


def print_single_age(age: int):
    """Print a single pixel character for the given age."""
    if age < 0:
        print(f"Invalid age: {age}")
        return

    if age <= 2:
        key = "baby"
    elif age <= 12:
        key = "child"
    elif age <= 19:
        key = "teen"
    elif age <= 35:
        key = "young_adult"
    elif age <= 55:
        key = "middle_aged"
    elif age <= 70:
        key = "elder"
    else:
        key = "very_elder"

    char = CHARACTERS[key]
    lines = render_character(key)
    laws_here = get_laws_unlocked_at(age)
    all_laws = get_laws_at_age(age)

    print()
    print(colorize(f"  Age {age} — {char['label']}", Color.BRIGHT_WHITE + Color.BOLD))
    print(colorize("  " + char["age"], Color.BRIGHT_YELLOW))
    print()

    # Side-by-side: pixel art on left, laws on right
    art_width = 22  # approx display width of pixel art block
    law_lines = []
    if laws_here:
        law_lines.append(colorize("  🇺🇸 Unlocked at this age:", Color.BRIGHT_CYAN))
        for _, name, desc, emoji in laws_here:
            law_lines.append(f"     {emoji} {colorize(name, Color.BRIGHT_WHITE)}")
    if all_laws and not laws_here:
        law_lines.append(colorize("  🇺🇸 Rights so far:", Color.BRIGHT_CYAN))
        for a, name, _, emoji in all_laws[-3:]:
            law_lines.append(f"     {emoji} {colorize(name, Color.BRIGHT_BLACK)} (age {a})")

    max_rows = max(len(lines), len(law_lines))
    for i in range(max_rows):
        art_part = ("    " + lines[i]) if i < len(lines) else " " * 18
        law_part = ("    " + law_lines[i]) if i < len(law_lines) else ""
        print(art_part + law_part)
    print()


def print_age_progression(start: int = 0, end: int = 80, step: int = 10, animated: bool = True):
    """Show age progression with pixel characters."""
    print()
    print(colorize("  Age Progression / 年龄演变", Color.BRIGHT_CYAN))
    print(colorize("  " + "─" * 50, Color.BRIGHT_BLACK))

    ages = list(range(start, end + 1, step))
    stage_keys = []
    for age in ages:
        if age <= 2:
            stage_keys.append(("baby", age))
        elif age <= 12:
            stage_keys.append(("child", age))
        elif age <= 19:
            stage_keys.append(("teen", age))
        elif age <= 35:
            stage_keys.append(("young_adult", age))
        elif age <= 55:
            stage_keys.append(("middle_aged", age))
        elif age <= 70:
            stage_keys.append(("elder", age))
        else:
            stage_keys.append(("very_elder", age))

    rendered = [(render_character(k), age) for k, age in stage_keys]
    max_height = max(len(r) for r, _ in rendered)
    for r, _ in rendered:
        while len(r) < max_height:
            r.append("  " * 7)

    GROUP_SIZE = 5
    for g_start in range(0, len(rendered), GROUP_SIZE):
        group = rendered[g_start:g_start + GROUP_SIZE]
        for row_idx in range(max_height):
            line = "  "
            for r, _ in group:
                line += r[row_idx] + "   "
            print(line)
            if animated:
                time.sleep(0.01)

        label_line = "  "
        for _, age in group:
            label_line += colorize(f"Age {age}".center(17), Color.BRIGHT_YELLOW) + "  "
        print(label_line)
        print()


def main():
    args = sys.argv[1:]
    no_anim = "--no-anim" in args
    args = [a for a in args if a != "--no-anim"]

    if not args or args[0] in ("-h", "--help"):
        print_all_ages(animated=not no_anim)
        print(colorize("  Usage:", Color.BRIGHT_WHITE))
        print("    python3 pixel_character.py              # Show all ages")
        print("    python3 pixel_character.py <age>        # Show single age + US laws")
        print("    python3 pixel_character.py --progress   # Age progression 0→80")
        print("    python3 pixel_character.py --laws       # 🇺🇸 US age milestone laws")
        print("    python3 pixel_character.py --no-anim    # No animation")
        print()
        return

    if args[0] == "--laws":
        print_us_laws_timeline(animated=not no_anim)
        return

    if args[0] == "--progress":
        print_age_progression(animated=not no_anim)
        return

    try:
        age = int(args[0])
        print_single_age(age)
    except ValueError:
        print(f"Unknown argument: {args[0]}")
        print("Run with --help for usage.")


if __name__ == "__main__":
    main()
