# UI Design Spec

## Purpose
- This document describes the current UI design of the Windows quota monitor so another AI or engineer can reproduce, extend, or port the interface without guessing.
- It documents the visual structure only. Business logic and app-server protocol behavior are intentionally out of scope except where they directly affect UI states.

## Product Surface
- Surface type: desktop floating utility panel
- Platform baseline: Windows desktop
- Window style: borderless, transparent host window with no taskbar presence
- Interaction model:
  - always-on-top small floating panel
  - draggable from the panel body
  - hidden to tray instead of behaving like a normal app window
  - tray icon and tray context menu are part of the overall UI system

## Core Visual Concept
- The UI is intentionally minimal and focused on live quota monitoring.
- The main panel contains only two vertically stacked quota pills:
  - top pill: `5h`
  - bottom pill: `1w`
- Each pill is a compact capsule with:
  - a ring on the left
  - a small label at the upper-right area
  - a large percentage in the center-right area
  - an `Until ...` line below the percentage
- The overall look should feel:
  - compact
  - polished
  - low-noise
  - softly futuristic
  - not dashboard-heavy

## Window Layout
- Real window size:
  - width: `216`
  - height: `190`
  - min width: `216`
  - min height: `190`
- Window background:
  - transparent
- Window chrome:
  - none
- The actual design is rendered inside a `Viewbox` over a fixed logical canvas:
  - logical width: `334`
  - logical height: `300`
- Vertical structure of the logical canvas:
  - first pill row: `146`
  - gap row: `8`
  - second pill row: `146`

## Pill Design
- Pill shape:
  - rounded capsule
  - corner radius: `42`
- Pill base color:
  - `RGB(74, 74, 74)` / `#4A4A4A`
- Shadow:
  - blur radius: `18`
  - shadow depth: `6`
  - opacity: `0.16`
  - color: black
- Outer margin per pill:
  - left/right: `20`
  - top/bottom: `16`
- Inner content margin per pill:
  - horizontal: `18`
  - vertical: `14`

## Pill Internal Layout
- Pill content uses a 3-column structure:
  - left ring column: `90`
  - spacer: `10`
  - right text column: remaining width
- Text column alignment:
  - label is aligned to top-right
  - main percentage and subtitle are centered as a group

## Ring Design
- Ring control:
  - custom vector ring with rounded caps
  - current implementation: `QuotaRing`
- Ring size:
  - width: `78`
  - height: `78`
- Ring thickness:
  - visible stroke thickness: `6`
- Ring rendering behavior:
  - draw background track as full circle
  - draw quota progress arc clockwise from top
  - add a soft glow around the active arc
- Glow behavior:
  - glow thickness is slightly larger than the visible stroke
  - glow is derived from the active ring color
  - glow is intentionally soft, not neon-heavy

## Color System
- `5h` active ring:
  - ring color: `#12FFA6`
  - track color: `#32755A`
- `1w` active ring:
  - ring color: `#5FE8FF`
  - track color: `#2D6570`
- Shared text colors in active mode:
  - label: `#DDEFEFEF`
  - main percentage: white
  - subtitle: `#F1F3F4`
- Inactive or stale mode colors:
  - `5h` ring: `#5E9D86`
  - `5h` track: `#26382F`
  - `1w` ring: `#6C949E`
  - `1w` track: `#24373B`
  - label: `#88A1A5A5`
  - main percentage: `#B5C3C6C6`
  - subtitle: `#8EA0A4A6`

## Typography
- Font family:
  - `Segoe UI Semibold`
- `5h` / `1w` label:
  - size: `15`
  - top-right placement
- Main percentage:
  - size: `40`
  - centered in the right-side content area
- Subtitle:
  - text format: `Until ...`
  - size: `18`
  - slight upward spacing adjustment: margin `2,-2,0,0`
- Time formatting rules:
  - `5h` pill only shows time like `Until 14:30`
  - `1w` may show either `HH:mm` for same-day reset or `MM-dd HH:mm` for later resets

## Content Rules
- Top pill always represents `5h` quota
- Bottom pill always represents `1w` quota
- Percentage text is integer style:
  - examples: `94%`, `60%`
- Subtitle always uses `Until`
- No extra data should appear in the main panel:
  - no charts
  - no tabs
  - no sync button
  - no settings button in the panel body
  - no close button in the panel body

## UI States
- There are two important visual states:

### Live state
- Trigger:
  - the app has received fresh quota data during the current run
- Visual behavior:
  - ring colors use the bright active palette
  - text uses bright palette
  - panel looks fully active

### Dim or stale state
- Trigger:
  - app startup before fresh quota arrives
  - offline state
  - degraded connection
  - disconnected state
  - cached quota shown without current live confirmation
- Visual behavior:
  - same layout and same values can remain visible
  - ring and text colors become muted
  - this state must clearly signal “not currently live” without replacing the whole layout

### Missing Codex state
- Trigger:
  - local Codex executable cannot be found
- Visual behavior:
  - still render the same pill structure
  - placeholder values are acceptable
  - UI should not collapse into a different page

## Tray UI
- Tray icon style:
  - dark rounded-square base
  - two colored ring segments inspired by the panel ring colors
  - small bright center block
  - should visually read as a quota monitor, not a generic app letter icon
- Tray menu style:
  - dark rounded rectangle
  - soft drop shadow
  - hover-highlighted rows
  - left icons, right text
- Tray menu items:
  - `Show Window` or `Hide Window` depending on visibility
  - `Locate Codex`
  - `Quit`
- `Locate Codex` should always be visible

## Non-Goals
- Do not reintroduce historical charts
- Do not turn the panel into a large dashboard
- Do not add heavy gradients or colorful backgrounds to the main pills
- Do not make the UI look like a settings app
- Do not replace the two-pill identity with cards, tabs, or list rows

## Design Intent Summary
- Think of the panel as a small always-visible quota ornament for the desktop.
- It should feel more like a premium system accessory than a business dashboard.
- The pills are the product identity:
  - dark capsule body
  - one elegant ring
  - one strong percentage
  - one small deadline line
- If future redesigns are made, preserve:
  - the dual-pill vertical composition
  - the ring-left / text-right anatomy
  - the live vs stale dimming behavior
  - the restrained, polished visual density
