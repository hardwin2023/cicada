"""The look: the Mac app's, drawn with GTK (canvas "知了 Linux · 对齐 Mac"). Its palette (AGENTS.md ›
Design): ground #F3F4F6, white sheets, ink #15171C, one accent #E8552B for "live", greys #5A5F6B /
#6B7080. Sizes are the Mac's numbers in px (text() turns them into points, which GTK renders 4/3
larger); every widget the theme would draw (switches, dropdowns, title buttons) is styled here, so
Yaru's orange and its large controls never show."""
from __future__ import annotations

import math

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from ..core.strings import L  # noqa: E402

CSS = b"""
* { font-family: "Noto Sans", sans-serif; font-size: 13px; }
.ground { background-color: #F3F4F6; }
.sheet, .sheet viewport { background-color: #FFFFFF; }
.soft-bar { background-color: #F3F4F6; }
.pinned-bar { background-color: #FFFFFF; border-bottom: 1px solid #ECEDF0; }
button.pinned-title { background: none; border: none; box-shadow: none; padding: 0; min-height: 0; }

/* Header bars: flat, the window buttons small glyphs (the Mac's quiet chrome, not Yaru's discs). */
headerbar.cicada { background-image: none; background-color: #FFFFFF; border: none; box-shadow: none; min-height: 44px; padding: 0 6px; }
headerbar.cicada.ground-bar { background-color: #F3F4F6; }
headerbar.cicada .title { font-weight: 700; font-size: 13px; color: #15171C; }
headerbar.cicada button.titlebutton { background-image: none; background-color: transparent; border: none; box-shadow: none; min-width: 26px; min-height: 26px; padding: 0; margin: 0 1px; border-radius: 6px; color: #6B7080; -gtk-icon-shadow: none; }
headerbar.cicada button.titlebutton:hover { background-color: rgba(21,23,28,0.07); color: #15171C; }
headerbar.cicada button.titlebutton image { -gtk-icon-transform: scale(0.8); }
headerbar.cicada separator { background: none; min-width: 4px; }
headerbar.records-bar { padding-left: 0; }
.sidebar-top { background-color: #F3F4F6; border-right: 1px solid #E4E6EA; margin: 0; }

.ink { color: #15171C; }
.body { color: #3D4149; }
.secondary { color: #5A5F6B; }
.tertiary { color: #6B7080; }
.accent { color: #E8552B; }
.link { color: #B33A14; }
.warn { color: #B23A12; }
.ok { color: #1F6B3A; }
.heading { font-weight: 700; color: #15171C; }
.mono { font-family: "Ubuntu Sans Mono", monospace; }

/* Buttons: 28 px, 12 px text, 7 px corners, as on the Mac. */
button { min-height: 22px; font-size: 12px; -gtk-icon-shadow: none; text-shadow: none; }
button.pill { border-radius: 14px; padding: 3px 12px; }
button.accentbtn { background-image: none; background-color: #E8552B; color: #FFFFFF; border: none; box-shadow: none; font-weight: 500; }
button.accentbtn:hover { background-color: #D44A22; }
button.accentbtn image, button.darkbtn image { color: #FFFFFF; }
button.darkbtn { background-image: none; background-color: #15171C; color: #FFFFFF; border: none; box-shadow: none; border-radius: 7px; padding: 4px 14px; }
button.darkbtn:hover { background-color: #2A2D34; }
button.darkbtn:disabled { background-color: #C9CCD3; }
button.darkbtn:disabled label { color: #FFFFFF; }
button.darkbtn.pill { border-radius: 14px; }
button.livepill { background-image: none; background-color: #FDEEE8; color: #B33A14; border: none; box-shadow: none; }
button.outline { background-image: none; background-color: #FFFFFF; border: 1px solid #E4E6EA; box-shadow: none; border-radius: 7px; padding: 3px 10px; color: #15171C; }
button.outline:hover { background-color: #F6F7F9; }
button.quietbtn { background-image: none; background-color: transparent; border: none; box-shadow: none; border-radius: 7px; padding: 3px 8px; color: #15171C; }
button.quietbtn:hover { background-color: rgba(21,23,28,0.06); }
button.dangertext { background-image: none; background-color: transparent; border: none; box-shadow: none; color: #B3261E; padding: 3px 10px; }
button.dangertext:hover { background-color: rgba(179,38,30,0.07); }
button.iconbtn { background-image: none; background-color: transparent; border: none; box-shadow: none; border-radius: 7px; min-width: 28px; min-height: 28px; padding: 0; color: #5A5F6B; }
button.iconbtn:hover { background-color: rgba(21,23,28,0.07); color: #15171C; }
button.iconbtn.stop { background-color: #FDEEE8; color: #E8552B; }
button.iconbtn.stop image { color: #E8552B; }
button.linkrow { background-image: none; background-color: transparent; border: none; box-shadow: none; border-radius: 0; padding: 0; }
button.linkrow:hover { background-color: #F6F7F9; }

/* The widgets the theme would draw. */
switch { background-image: none; background-color: #D5D8DE; border: none; box-shadow: none; border-radius: 10px; min-width: 15px; min-height: 18px; font-size: 0; color: transparent; }
switch:checked { background-color: #15171C; }
switch slider { background-image: none; background-color: #FFFFFF; border: none; border-radius: 8px; min-width: 14px; min-height: 14px; margin: 2px; box-shadow: 0 1px 2px rgba(0,0,0,0.25); }
switch image { color: transparent; -gtk-icon-transform: scale(0); }
combobox button, combobox button.combo { background-image: none; background-color: #FFFFFF; border: 1px solid #E4E6EA; box-shadow: none; border-radius: 6px; min-height: 22px; padding: 1px 6px 1px 8px; color: #15171C; }
combobox button:hover { background-color: #F6F7F9; }
combobox arrow { -gtk-icon-source: -gtk-icontheme("pan-down-symbolic"); min-width: 12px; min-height: 12px; color: #6B7080; }
combobox cellview, combobox button label { font-size: 12px; }
entry { background-image: none; background-color: #FFFFFF; border: 1px solid #E4E6EA; box-shadow: none; border-radius: 7px; min-height: 26px; padding: 0 9px; font-size: 13px; color: #15171C; caret-color: #15171C; }
entry:focus { border-color: #E8552B; box-shadow: 0 0 0 2px rgba(232,85,43,0.18); }
entry.error { border-color: #B3261E; }
entry.search { background-color: #E8EAEE; border-color: transparent; min-height: 28px; font-size: 12px; }
entry.search:focus { background-color: #FFFFFF; }
entry selection, label selection { background-color: rgba(232,85,43,0.22); color: #15171C; }
popover, popover.background { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 10px; box-shadow: 0 8px 24px rgba(21,23,28,0.14); padding: 0; }
menu, .menu, .context-menu { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 8px; padding: 4px; }
menu menuitem, .menu menuitem { font-size: 13px; padding: 4px 10px; border-radius: 5px; min-height: 22px; color: #15171C; }
menu menuitem:hover, .menu menuitem:hover { background-color: #F2F3F5; color: #15171C; }
menu menuitem:disabled label { color: #6B7080; font-size: 11px; }
scrollbar { background-color: transparent; border: none; }
scrollbar slider { background-color: rgba(21,23,28,0.22); border: none; border-radius: 4px; min-width: 6px; min-height: 6px; }
scrollbar slider:hover { background-color: rgba(21,23,28,0.38); }
tooltip, tooltip.background { background-color: #15171C; border-radius: 6px; border: none; box-shadow: none; }
tooltip label { color: #FFFFFF; font-size: 12px; }
spinner { color: #6B7080; }

.segmented { background-color: #F2F3F5; border-radius: 8px; padding: 2px; }
.segmented button { background-image: none; background-color: transparent; border: none; box-shadow: none; border-radius: 6px; min-height: 22px; padding: 0 10px; color: #5A5F6B; font-size: 12px; }
.segmented.big { border-radius: 10px; padding: 3px; }
.segmented.big button { min-height: 28px; border-radius: 8px; font-size: 13px; }
.segmented button:checked label { font-weight: 700; color: #15171C; }
.panel.dark .segmented { background-color: #2A2C32; }
.panel.dark .segmented button:checked { background-color: #3A3D45; }
.panel.dark .segmented button:checked label { color: #F2F3F5; }
.segmented button:checked { background-color: #FFFFFF; color: #15171C; box-shadow: 0 1px 2px rgba(0,0,0,0.10); font-weight: 500; }

.endingstrip { background-color: #FDEEE8; border-radius: 12px; }
.notice { background-color: #F2F3F5; border-radius: 12px; }
dialog.endask { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 12px; }
/* The share dialog (ShareViews.swift): the review's hits on the accent's pale, the link and password on the fill. */
.sharehit { background-color: #FCEDE7; border-radius: 8px; }
.sharefield { background-color: #F2F3F5; border-radius: 6px; }
/* The share dialog's Copy and its arrow as one control (a linked box). */
.copybtn button.outline:first-child { border-top-right-radius: 0; border-bottom-right-radius: 0; }
.copybtn button.outline.arrow { border-top-left-radius: 0; border-bottom-left-radius: 0; border-left-width: 0; padding: 3px 5px; }
.copybtn button.outline.arrow image { color: #5A5F6B; }
dialog.sharesheet separator { background-color: #EEF0F3; min-height: 1px; }
dialog.sharesheet entry.mono { font-family: "Ubuntu Sans Mono", monospace; }
.notice.error { background-color: #FDECEA; }
/* StatusLine (Views.swift): a service in trouble in one line on the plain fill; colour only in the dot. */
.statusline { background-color: #F2F3F5; border-radius: 10px; min-height: 36px; }
.statusdot { border-radius: 3px; min-width: 6px; min-height: 6px; background-color: #6B7080; }
.statusdot.waiting { background-color: #C98A00; }
.statusdot.needsyou { background-color: #B42318; }
button.quietbtn.statusaction, button.quietbtn.statusaction:hover { background-color: transparent; padding: 4px 0; min-width: 0; }
.panel.dark .endingstrip { background-color: rgba(232,85,43,0.16); }
/* The light fills would sit as pale slabs, their grey text washed out, on the dark notes window. */
.panel.dark .statusline, .panel.dark .notice { background-color: #2A2C32; }
.panel.dark .notice.error { background-color: rgba(180,35,24,0.22); }
.panel.dark .segmented button { color: #A3A7B1; }
entry.notes-search { min-height: 32px; font-size: 13px; border-radius: 9px; }
.panel.dark entry.notes-search { background-color: #2A2C32; color: #F2F3F5; }
button.iconbtn.on { background-color: #F3F4F6; color: #15171C; }
.panel.dark button.iconbtn.on { background-color: #34363D; }
.wide > scrolledwindow:first-child { border-right: 1px solid #EEF0F3; }
.boxed { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 12px; }
.prow-top { border-top: 1px solid #EEF0F3; }
.warnrow { background-color: #FFF8F3; border-radius: 0 0 12px 12px; }
.warnrow label { color: #5A2A16; }
.group-title { font-weight: 700; color: #6B7080; }

.aitag { border-radius: 6px; }
.aitag.ok { background-color: #E3F3EA; }
.aitag.ok label { color: #1F6B3A; }
.aitag.off { background-color: #F2F3F5; }
.aitag.off label { color: #5A5F6B; }
.aitag.ling { background-color: #FDEEE8; }
.aitag.ling label { color: #B23A12; }
.aitag.warn { background-color: #FFF4D6; }
.aitag.warn label { color: #8A5A00; }
/* The AI service check (AICheckView.swift): a 20 px disc per step, the reason in red (busy in amber). */
.stepdisc { border-radius: 10px; min-width: 20px; min-height: 20px; }
.stepdisc.ok { background-color: #E3F3EA; }
.stepdisc.ok image { color: #1F6B3A; }
.stepdisc.fail { background-color: #FDECEA; }
.stepdisc.fail image { color: #B3261E; }
.stepdisc.busy { background-color: #FFF4D6; }
.stepdisc.busy image { color: #8A5A00; }
.stepdisc.running { background-color: #FDEEE8; }
.stepdisc.running image { color: #B33A14; }
.stepdisc.off { background-color: #F2F3F5; }
.stepdisc.off image { color: #6B7080; }
.stepwhy { color: #B3261E; }
.stepwhy.busy { color: #8A5A00; }
.proxybox { background-color: #F2F3F5; border-radius: 8px; }
.proxybox label { color: #3D4149; }
.warnstrip { background-color: #FFF4D6; border-radius: 10px; }
.warnstrip label { color: #8A5A00; }
.busyline { color: #8A5A00; }
.chip { background-color: #F2F3F5; border-radius: 5px; padding: 1px 6px; color: #15171C; }
.chip.now { background-color: #E8552B; color: #FFFFFF; }
.chip.time { background-color: transparent; padding: 0; color: #B33A14; }
.placetag { border-radius: 4px; border: 1px solid #E4E6EA; }
.placetag.room { background-color: #F2F3F5; border-color: #F2F3F5; }
.placetag label { color: #5A5F6B; }
/* Save to folder (folder_export_view.py): the Obsidian vault tag, a problem in the card (accent-pale
   when the folder refuses, ground grey otherwise), and the save-where choices (ink when picked). */
.foldertag { border-radius: 4px; background-color: #F2F3F5; }
.foldertag label { color: #5A5F6B; }
.folderproblem { background-color: #F3F4F6; border-radius: 9px; }
.folderproblem.denied { background-color: #FDEEE8; }
button.folderoption { background-image: none; background-color: #FFFFFF; border: 1px solid #E4E6EA; box-shadow: none; border-radius: 9px; padding: 0; }
button.folderoption:hover { background-color: #F6F7F9; }
button.folderoption.picked, button.folderoption.picked:hover { background-color: #FFFFFF; border: 1.5px solid #15171C; }
button.folderoption image { color: #6B7080; }
button.folderoption.picked image { color: #15171C; }
.metag { border-radius: 4px; border: 1px solid rgba(232,85,43,0.45); }
.metag label { color: #B33A14; }
.badge { background-color: #FDEEE8; border-radius: 5px; padding: 0 6px; color: #B33A14; }
.softcard { background-color: #F5F6F8; border-radius: 12px; }
.summarycard { background-color: #F5F6F8; border-radius: 12px; }
.icon-tile { background-color: #FDEEE8; border-radius: 16px; }
.icon-tile image { color: #E8552B; }
.icon-tile.grey { background-color: #F3F4F6; }
.icon-tile.grey image { color: #5A5F6B; }
.icon-tile.warn { background-color: #FDEEE8; }
.icon-tile.warn image { color: #B23A12; }
.wavebar { background-color: #C9CCD3; border-radius: 3px; }
.wavebar.on { background-color: #E8552B; }
.dotstep { background-color: #C9CCD3; border-radius: 3px; min-width: 6px; min-height: 6px; }
.dotstep.on { background-color: #E8552B; min-width: 18px; }
.livedot { background-color: #E8552B; border-radius: 4px; min-width: 7px; min-height: 7px; box-shadow: 0 0 0 3px rgba(232,85,43,0.18); }
/* "Live" without blinking (BreathingDot / BreathingMark): a ring swells out and fades. GTK has no
   transforms, so the ring is a growing box-shadow; GNOME's Reduce Animation turns CSS animations off. */
@keyframes breathe-dot { from { box-shadow: 0 0 0 0 rgba(232,85,43,0.6); } to { box-shadow: 0 0 0 6px rgba(232,85,43,0); } }
/* BreathingMark scales a logo-sized rounded square 1 -> 1.7 behind the 22 px logo: what shows is a band
   growing to 7.7 px, which is what a spread shadow from the logo's own rounded edge draws. */
@keyframes breathe-mark { from { box-shadow: 0 0 0 0 rgba(232,85,43,0.55); } to { box-shadow: 0 0 0 8px rgba(232,85,43,0); } }
/* BreathingDot (6 px, ring 1 -> 2.6): a 4.8 px band. */
@keyframes breathe-dot6 { from { box-shadow: 0 0 0 0 rgba(232,85,43,0.6); } to { box-shadow: 0 0 0 5px rgba(232,85,43,0); } }
.livedot.small { min-width: 6px; min-height: 6px; border-radius: 3px; box-shadow: none; }
.livedot.small.breathing { animation: breathe-dot6 2s ease-out infinite; }
.livedot.breathing { animation: breathe-dot 2s ease-out infinite; }
.breathemark { border-radius: 6px; animation: breathe-mark 2.2s ease-out infinite; }
.breathemark.late { animation-delay: 1.1s; }
.idledot { background-color: #C9CCD3; border-radius: 4px; min-width: 7px; min-height: 7px; }
/* The custom service's per-use rows: how each use is doing (AISettings.swift sectionHeader). */
separator.hairline { background-color: #E4E6EA; min-height: 1px; margin: 4px 0; }
.statedot { background-color: #C9CCD3; border-radius: 4px; min-width: 8px; min-height: 8px; }
.statedot.ok { background-color: #1F7A45; }
.statedot.warn { background-color: #8A5A00; }
.statedot.error { background-color: #B42318; }
.statedot.live { background-color: #E8552B; }

.sidebar { background-color: #F3F4F6; border-right: 1px solid #E4E6EA; }
.sidebar list, .sidebar viewport { background-color: #F3F4F6; }
.sidebar list row { border-radius: 8px; margin: 0 10px; padding: 0; }
.sidebar list row:selected, .sidebar list row:selected:hover { background-color: #E3E5EA; }
.sidebar list row:selected label { color: #15171C; }
.sidebar list row:hover { background-color: #ECEEF1; }
.group-label { font-weight: 700; color: #6B7080; }
.transcript-row { border-top: 1px solid #EEF0F3; }
/* With a recording: a lighter fill under the pointer (a click plays the line), the line playing on the pale accent. */
.transcript-row.hover { background-color: #F5F6F8; border-radius: 10px; border-top-color: transparent; }
.transcript-row.playing { background-color: #FCEDE7; border-radius: 10px; border-top-color: transparent; }
button.timelink { background-image: none; background-color: transparent; border: none; box-shadow: none; padding: 0; min-height: 0; min-width: 0; }
button.timelink:hover label { text-decoration-line: underline; }
.transcript-row button.timelink:hover label { text-decoration-line: none; }

/* The recording's player bar (RecordingPlayerBar): a soft box, a round ink play button, the played part in the accent. */
.playerbar { background-color: #F5F6F8; border-radius: 12px; }
.playerstrip { background-color: #FFFFFF; border-top: 1px solid #F0F1F4; }
/* "Back to playing - m:ss", over the bottom of the page once it is scrolled away from what plays. */
button.backpill { background-image: none; background-color: #15171C; border: none; border-radius: 17px; min-height: 34px; padding: 0 16px; box-shadow: 0 4px 10px rgba(21,23,28,0.18); }
button.backpill:hover { background-color: #2A2D34; }
button.backpill label { color: #FFFFFF; }
.pillwave .stick { background-color: #FFFFFF; border-radius: 1px; }
/* PlayingBars: three accent capsules bouncing beside the line that plays. */
.playbars .stick { background-color: #E8552B; border-radius: 2px; }
button.playround { background-image: none; background-color: #15171C; border: none; box-shadow: none; border-radius: 16px; min-width: 32px; min-height: 32px; padding: 0; }
button.playround:hover { background-color: #2A2D34; }
button.playround image { color: #FFFFFF; }
button.ratebtn { background-image: none; background-color: #FFFFFF; border: none; box-shadow: none; border-radius: 6px; min-height: 0; min-width: 0; padding: 2px 7px; }
button.ratebtn:hover { background-color: #ECEEF1; }
scale.playerscale { padding: 0; margin: 0; }
scale.playerscale trough { background-image: none; background-color: #E2E4E9; border: none; box-shadow: none; border-radius: 2px; min-height: 4px; }
scale.playerscale highlight { background-image: none; background-color: #E8552B; border: none; border-radius: 2px; min-height: 4px; }
scale.playerscale slider { background-image: none; background-color: #FFFFFF; border: 1px solid #D5D8DE; box-shadow: 0 1px 2px rgba(0,0,0,0.18); border-radius: 7px; min-width: 12px; min-height: 12px; margin: -5px 0; }
scale.playerscale slider:hover { background-color: #FFFFFF; border-color: #B9BDC6; }
.spk1 { color: #0F7B6C; } .spk2 { color: #7A4CC2; } .spk3 { color: #B03A7A; } .spk4 { color: #8A5A00; }
button.spkchip { background-image: none; background-color: #F2F3F5; border: none; box-shadow: none; border-radius: 11px; padding: 0 9px; min-height: 22px; }
button.spkchip:hover { background-color: #E8EAEE; }
button.spklabel { background-image: none; background-color: transparent; border: none; box-shadow: none; padding: 0 4px 0 0; min-height: 0; }
button.spklabel:hover { background-color: #F3F4F6; }
button.pick { background-image: none; background-color: #FFFFFF; border: 1px solid #E4E6EA; box-shadow: none; border-radius: 7px; padding: 1px 9px; min-height: 24px; }
button.pick.chosen { background-color: #15171C; color: #FFFFFF; border-color: #15171C; }
button.underline label { text-decoration-line: underline; }

/* The listening capsule in the records window's header (ListenPill.swift). */
button.listenpill { background-image: none; background-color: #FFFFFF; border: 1px solid #E4E6EA; box-shadow: none; border-radius: 16px; min-height: 30px; padding: 0 12px 0 6px; }
button.listenpill:hover { background-color: #F8F9FA; }
.listenpill.live { background-color: #15171C; border-radius: 16px; padding: 4px 4px 4px 5px; min-height: 24px; }
/* monospacedDigit: the clock and the countdown don't shift every second. */
.listenpill.live.ending { padding-left: 4px; }
label.tnum { font-feature-settings: "tnum"; }
label.err { color: #B23A12; }
/* In the header bar Yaru pads every button to 36 px; the capsule's are the Mac's 24. */
headerbar .listenpill.live button.pillshow, headerbar .listenpill.live button.pillend, headerbar .listenpill.live button.pillkeep {
  min-height: 24px; margin: 0; padding-top: 0; padding-bottom: 0; border: none; }
headerbar .listenpill.live button.pillshow { padding: 0; }
.listenpill.live label { color: #FFFFFF; }
button.pillshow { background-image: none; background-color: transparent; border: none; box-shadow: none; padding: 0; min-height: 24px; }
button.pillend { background-image: none; background-color: #2F323A; color: #FFFFFF; border: none; box-shadow: none; border-radius: 12px; min-height: 24px; padding: 0 12px; font-weight: 700; }
button.pillend:hover { background-color: #3A3D46; }
button.pillend label { color: #FFFFFF; }
button.pillkeep { background-image: none; background-color: #FFFFFF; color: #15171C; border: none; box-shadow: none; border-radius: 12px; min-height: 24px; padding: 0 12px; font-weight: 700; }
button.pillkeep:hover { background-color: #ECEEF1; }
button.pillkeep label { color: #15171C; }
.listenpill.live button.pillkeep label { color: #15171C; }
.listenpill.live label.countdown { color: #F4A58C; }
.listenpill.live label.dim { color: #BDC0C7; }
.pillsep { background-color: #E4E6EA; min-width: 1px; min-height: 14px; }
.meterbar { background-color: #E8552B; border-radius: 2px; }
.toast { background-color: #15171C; border-radius: 10px; padding: 2px 4px 2px 14px; box-shadow: 0 6px 18px rgba(0,0,0,0.22); }
.toast label { color: #F2F3F5; }
.toast button { background-image: none; background-color: rgba(255,255,255,0.12); color: #FFFFFF; border: none; box-shadow: none; border-radius: 6px; padding: 1px 10px; }
.toast button label { color: #FFFFFF; }
.toast button.undo { background-color: transparent; padding: 1px 6px; }
.toast button.undo label { color: #FFB59C; font-weight: 700; }

/* Fixing misheard words: a fixed word's chip, the confirm card, the review banner. */
.fixchip { background-color: #F2F3F5; border-radius: 6px; }
.panel.dark .fixchip { background-color: #2A2C32; }
button.fixlink { background: none; border: none; box-shadow: none; padding: 0; min-height: 0; color: #B33A14; font-size: 11px; font-weight: 500; }
button.fixlink label { color: #B33A14; }
.fixcard { background-color: #FFFFFF; border: 1px solid rgba(0,0,0,0.08); border-radius: 10px; box-shadow: 0 4px 10px rgba(0,0,0,0.08); }
.panel.dark .fixcard { background-color: #22242A; border-color: #3A3C43; }
.fixbanner { background-color: #FEF6F2; border: 1px solid #FBE0D5; border-radius: 12px; }
button.softbtn { background-image: none; background-color: #ECEDF0; border: none; box-shadow: none; border-radius: 7px; padding: 4px 14px; color: #5A5F6B; }
button.softbtn:hover { background-color: #E2E4E8; }
button.softbtn:disabled { background-color: #F3F4F6; color: #A3A7B1; }
button.softbtn:disabled label { color: #A3A7B1; }
.fixeditor { border: 1px solid #15171C; border-radius: 8px; background-color: #FFFFFF; }
.fixeditor text { background-color: #FFFFFF; color: #15171C; }
.heardchip { background-color: #F2F3F5; border-radius: 5px; }
.dashed { border: 1px dashed #CDD0D6; border-radius: 9px; }

.notes-window { background-color: transparent; }
.panel .speakbox { background-color: #FDEEE8; border-radius: 12px; }
.panel.dark .speakbox { background-color: rgba(232,85,43,0.14); }
.panel { background-color: #FFFFFF; border-radius: 14px; border: 1px solid #E4E6EA; }
/* The live caption: a dark card at the bottom of the notes window, as on the Mac. */
.panel .livebox { background-color: #15171C; border-radius: 14px; }
.panel .livebox .ink, .panel .livebox .heading { color: #FFFFFF; }
.panel .livebox .secondary, .panel .livebox .tertiary { color: #BDC0C7; }
.panel .livebox .accent { color: #F08A6C; }
.panel .livebox .spk1 { color: #5CC8B5; } .panel .livebox .spk2 { color: #B79BF0; }
.panel .livebox .spk3 { color: #F08FBF; } .panel .livebox .spk4 { color: #E3B45C; }
.panel .livebox .icon-tile.grey { background-color: #2A2C32; }
.panel .livebox .icon-tile.grey image, .panel .livebox .icon-tile.warn image { color: #BDC0C7; }
.panel .livebox .icon-tile.warn { background-color: rgba(232,85,43,0.22); }
.panel .livebox button.outline { background-color: #2A2C32; border-color: #3A3C43; color: #F2F3F5; }
.panel .livebox.light { background-color: #F3F4F6; }
.panel .livebox.light .ink, .panel .livebox.light .heading { color: #15171C; }
.panel .livebox.light .secondary, .panel .livebox.light .tertiary { color: #5A5F6B; }
.panel .livebox.light .icon-tile.grey { background-color: #FFFFFF; }
.panel .livebox.light .icon-tile.grey image { color: #5A5F6B; }
.panel .livebox.light .icon-tile.warn image { color: #B23A12; }
.panel .livebox.light button.outline { background-color: #FFFFFF; border-color: #E4E6EA; color: #15171C; }
.panel .footer { border-top: none; }
.panel.dark .livebox.light { background-color: #2A2C32; }
.panel.dark .livebox.light .ink, .panel.dark .livebox.light .heading { color: #F2F3F5; }
.panel.dark .livebox.light .secondary, .panel.dark .livebox.light .tertiary { color: #A3A7B1; }
.panel.dark .livebox.light .icon-tile.grey { background-color: #34363D; }
.panel.dark .livebox.light .icon-tile.grey image { color: #A3A7B1; }
.panel.dark .livebox.light button.outline { background-color: #34363D; border-color: #3A3C43; color: #F2F3F5; }
.panel.dark { background-color: #1F2025; border-color: #34363D; }
.panel.dark .livebox { background-color: #2E3037; }
.panel.dark .ink, .panel.dark .heading, .panel.dark button.iconbtn, .panel.dark button.iconbtn image { color: #F2F3F5; }
.panel.dark .body { color: #D4D6DB; }
.panel.dark .secondary, .panel.dark .tertiary { color: #A3A7B1; }
.panel.dark .chip { background-color: #34363D; color: #F2F3F5; }
.panel.dark .chip.now { background-color: #E8552B; }
.panel.dark .chip.time { background-color: transparent; color: #F08A6C; }
.panel.dark .placetag { border-color: #44474F; }
.panel.dark .placetag.room { background-color: #34363D; border-color: #34363D; }
.panel.dark .placetag label { color: #A3A7B1; }
.panel.dark .metag label { color: #F08A6C; }
.panel.dark .link { color: #F08A6C; }
.panel.dark .badge { background-color: rgba(232,85,43,0.18); color: #F08A6C; }
.panel.dark button.iconbtn:hover { background-color: rgba(255,255,255,0.08); }
.panel.dark button.iconbtn.stop { background-color: rgba(232,85,43,0.18); }
.panel.dark button.iconbtn.stop image { color: #E8552B; }
.panel.dark .icon-tile.grey { background-color: #34363D; }
.panel.dark .icon-tile.grey image { color: #A3A7B1; }
.panel.dark .icon-tile.warn { background-color: rgba(232,85,43,0.16); }
.panel.dark button.outline { background-color: #2A2C32; border-color: #3A3C43; color: #F2F3F5; }

/* Listening, no notes asked for yet (NotesListeningView): a pale-accent row with SoundBars, then the
   notes' shape shimmering. Both move by CSS alone, so GNOME's Reduce Animation stops them. */
.listenrow { background-color: rgba(252,237,231,0.7); border-radius: 12px; }
.panel.dark .listenrow { background-color: rgba(232,85,43,0.14); }
/* SoundBars: four 3 px bars of fixed size whose orange fill grows 30% -> 100% from the middle (a
   background, so nothing is laid out again 30 times a second); each lags the last by 0.15 s. */
@keyframes soundbar { 0% { background-size: 100% 30%; } 50% { background-size: 100% 100%; } 100% { background-size: 100% 30%; } }
.soundbar { min-width: 3px; min-height: 22px; border-radius: 2px; background-image: linear-gradient(#E8552B, #E8552B);
            background-repeat: no-repeat; background-position: center; background-size: 100% 60%;
            animation: soundbar 1.1s ease-in-out infinite; }
.soundbar.b1 { animation-delay: -0.95s; } .soundbar.b2 { animation-delay: -0.8s; } .soundbar.b3 { animation-delay: -0.65s; }
/* SkeletonBar: a light sweeping left to right every 1.4 s. The gradient is three bars wide, so moving
   it from 100% to 0% takes its light (+-0.6 of a bar around the middle) from -0.5 to 1.5, the Mac's. */
@keyframes shimmer { from { background-position: 100% 0; } to { background-position: 0% 0; } }
.skeleton { border-radius: 5px; background-color: #EEF0F3; background-repeat: no-repeat; background-size: 300% 100%;
            background-image: linear-gradient(to right, #EEF0F3 0%, #EEF0F3 30%, #F7F8FA 50%, #EEF0F3 70%, #EEF0F3 100%);
            animation: shimmer 1.4s linear infinite; }
.skeleton.thin { border-radius: 4px; }
.panel.dark .skeleton { background-color: #2E3037;
            background-image: linear-gradient(to right, #2E3037 0%, #2E3037 30%, #3A3C43 50%, #2E3037 70%, #2E3037 100%); }
.ghost { color: #B8BDC6; }
.panel.dark .ghost { color: #5A5F6B; }
.slot { border: 1.5px dashed #E4E6EA; border-radius: 12px; }
.panel.dark .slot { border-color: #3A3C43; }
.pill { background-color: #F2F3F5; border-radius: 13px; }
.panel.dark .pill { background-color: #34363D; }

levelbar trough { min-height: 6px; padding: 0; border: none; background-color: #ECEEF1; border-radius: 3px; }
levelbar block { min-height: 6px; border: none; border-radius: 3px; }
levelbar block.filled, levelbar block.low, levelbar block.high, levelbar block.full { background-color: #E8552B; }
levelbar block.empty { background-color: transparent; }
entry.keyentry { border-radius: 10px; min-height: 34px; }

/* Onboarding (Onboarding.swift): 860 x 640 on the ground, white 18 px cards, a 44 px ink button. */
.stepbar { background-color: #DDDEE2; border-radius: 2px; min-height: 4px; }
.stepbar.on { background-color: #15171C; }
.bigcard { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 18px; }
.raised { background-color: #F6F7F9; border-radius: 8px; }
/* The own-voice row and sheet (VoicePicker.swift): an accent wash for the voice the room hears. */
.voicewash { background-color: #FFFAF8; }
.voicemeter { background-color: #FFFAF8; border-radius: 12px; }
.voicefail { background-color: #FDECEA; border-radius: 12px; }
.voicefail label { color: #B42318; }
.voicerows { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 14px; }
.voicepassage { background-color: #F6F7F9; border-radius: 14px; }
button.voiceplay { background-image: none; background-color: #F2F3F5; border: none; box-shadow: none; border-radius: 16px; min-width: 32px; min-height: 32px; padding: 0; color: #15171C; }
button.voiceplay.accent { background-color: #E8552B; color: #FFFFFF; }
button.voiceplay.accent image { color: #FFFFFF; }
button.voiceplay.accent spinner { color: #FFFFFF; }
checkbutton.voicecheck check { background-image: none; background-color: #FFFFFF; border: 1px solid #B8BCC4; border-radius: 4px; min-width: 14px; min-height: 14px; box-shadow: none; color: transparent; }
checkbutton.voicecheck check:checked { background-color: #15171C; border-color: #15171C; color: #FFFFFF; }
checkbutton.voicecheck check:disabled { background-color: #F3F4F6; }
checkbutton.voicecheck check:checked:disabled { background-color: #8A8E98; border-color: #8A8E98; }
.voicetag { background-color: #E8552B; color: #FFFFFF; border-radius: 5px; padding: 1px 6px; }
.midcard { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 12px; }
.tipcard { background-color: #FFFFFF; border-radius: 14px; }
.hair { background-color: #E4E6EA; min-height: 1px; }
.srccard { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 14px; }
.srccard.on { border: 2px solid #15171C; }
.srcbadge { background-color: #F3F4F6; border-radius: 5px; padding: 0 6px; }
.srcbadge label { color: #5A5F6B; }
.srcstep { background-color: #F3F4F6; border-radius: 6px; padding: 1px 7px 2px 7px; }
.srcstep label { color: #15171C; }
.srcstep.on { background-color: #15171C; }
.srcstep.on label { color: #FFFFFF; }
.srccard flowbox, .srccard flowboxchild { padding: 0; background: none; }
button.quietbtn.greytext label { color: #5A5F6B; }
button.ctapill { background-image: none; background-color: #15171C; border: none; box-shadow: none; border-radius: 22px; min-height: 44px; padding: 0 22px; }
button.ctapill:hover { background-color: #2A2D34; }
button.ctapill label { color: #FFFFFF; }
.ctakeys { border: 1px solid rgba(255,255,255,0.35); border-radius: 5px; }
.ctakeys label { color: #BDC0C7; }
.setupcard { background-color: #F7F8FA; border-radius: 16px; }
.setupdisc { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 13px; }
.setupdisc label { color: #3A3E48; }
.setupdisc.done { background-color: #15171C; border-color: #15171C; }
.setupdisc.done image { color: #FFFFFF; }
.setupdisc.now { background-color: #E8552B; border-color: #E8552B; }
.setupdisc.now label { color: #FFFFFF; }
.setuptag { background-color: #FFFFFF; border: 1px solid #E4E6EA; border-radius: 9px; padding: 0 7px; }
.stepnum { background-color: #15171C; border-radius: 12px; min-width: 24px; min-height: 24px; }
.stepnum label { color: #FFFFFF; }
button.bigbtn { background-image: none; background-color: #15171C; color: #FFFFFF; border: none; box-shadow: none; border-radius: 12px; min-height: 44px; padding: 0 28px; font-size: 14px; font-weight: 700; }
button.bigbtn:hover { background-color: #2A2D34; }
button.bigbtn label, button.bigbtn image { color: #FFFFFF; }
button.bigbtn.waiting { background-color: #DDDEE2; }
button.bigbtn.waiting label, button.bigbtn.waiting image { color: #5A5F6B; }
button.bigquiet { font-size: 13px; color: #5A5F6B; }
button.bigquiet label { color: #5A5F6B; }
button.midbtn { min-height: 36px; border-radius: 10px; padding: 0 16px; font-size: 13px; font-weight: 700; }
button.outline.midbtn { border-color: #D6D6D6; }
.samplestage { background-color: #23262D; border-radius: 18px; }
.stage-dim { color: #BDC0C7; }
.stage-ink { color: #FFFFFF; }
button.bigplay { min-height: 36px; border-radius: 18px; padding: 0 18px; font-size: 13px; }
button.bigplay image { color: #15171C; }
button.choicecard { background-image: none; background-color: #FFFFFF; border: 1px solid #E4E6EA; box-shadow: none; border-radius: 16px; padding: 0; }
button.choicecard:hover { border-color: #15171C; }
.keycap { background-color: #FFFFFF; border: 1px solid #D6D6D6; border-bottom-width: 4px; border-radius: 10px; }
.topbar { background-color: #1D1E22; border-radius: 17px 17px 0 0; }
.topbar-ink { color: #E9EAEE; }
.topbar-pill { background-color: #34363C; border-radius: 10px; }
.topbar-ring { background-color: rgba(232,85,43,0.22); border: 1.5px solid #E8552B; border-radius: 7px; }
"""


def install_css() -> None:
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def prefers_dark() -> bool:
    """GNOME's 外观 › 深色 (org.gnome.desktop.interface color-scheme), else the GTK theme's name."""
    try:
        source = Gio.SettingsSchemaSource.get_default()
        if source and source.lookup("org.gnome.desktop.interface", True):
            s = Gio.Settings.new("org.gnome.desktop.interface")
            if "color-scheme" in s.list_keys() and s.get_string("color-scheme") == "prefer-dark":
                return True
    except GLib.Error:
        pass
    theme = Gtk.Settings.get_default().get_property("gtk-theme-name") or ""
    return theme.lower().endswith("-dark")


def classes(widget, *names):
    ctx = widget.get_style_context()
    for n in names:
        for one in (n or "").split():
            ctx.add_class(one)
    return widget


# The language text is tagged with, so fontconfig picks the matching CJK face: Japanese kanji drawn
# with the Chinese font look wrong to a Japanese reader (and the other way round). No CJK family is
# named in the CSS for that reason. Set from the UI language at start; content passes its own.
DEFAULT_LANG = "zh-cn"


def pango_lang(code: str | None) -> str:
    c = (code or "").lower()
    if c.startswith("zh"):
        return "zh-tw" if ("tw" in c or "hant" in c or "hk" in c) else "zh-cn"
    return c.split("-")[0] or DEFAULT_LANG


def text(s: str, size: int = 13, cls: str = "ink", bold: bool = False, wrap: bool = True, selectable: bool = False,
         ellipsize: bool = True, width_chars: int = 40, lang: str | None = None) -> Gtk.Label:
    l = Gtk.Label()
    l.set_xalign(0)
    l.cicada_format = (size, pango_lang(lang) if lang else DEFAULT_LANG, bold)
    retext(l, s)
    classes(l, cls)
    if wrap:
        l.set_line_wrap(True)
        l.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        # Wrapped text asks for a modest width and takes what it's given, so a long English line
        # doesn't stretch its window.
        l.set_max_width_chars(width_chars)
    elif ellipsize:
        l.set_ellipsize(Pango.EllipsizeMode.END)
    l.set_selectable(selectable)
    return l


def retext(l: Gtk.Label, s: str) -> None:
    """New text in a label made by text(), keeping its size, weight and language (set_text would drop them)."""
    size, lang, bold = l.cicada_format
    # `size` is the Mac's number, in px: Pango sizes are points (4/3 px at 96 dpi), so 0.75 of it;
    # in points, GNOME's text scaling still applies. Bold is the Mac's semibold (Noto has no 600).
    l.set_markup('<span size="%d" lang="%s"%s>%s</span>' % (round(size * 768), lang, ' weight="bold"' if bold else "", esc(s)))


def marked(s: str, terms: list, size: int = 13, cls: str = "ink", current: bool = False, lang: str | None = None) -> Gtk.Label:
    """text() with every search term highlighted in place (the current match in the accent)."""
    l = text(s, size, cls, lang=lang)
    low = s.lower()
    spans = []
    for t in terms:
        t = t.lower()
        i = low.find(t) if t else -1
        while i >= 0:
            spans.append((i, i + len(t)))
            i = low.find(t, i + len(t))
    if not spans:
        return l
    spans.sort()
    merged = []
    for a, b in spans:
        if merged and a <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(b, merged[-1][1]))
        else:
            merged.append((a, b))
    mark = ' background="#E8552B" foreground="#FFFFFF"' if current else ' background="#FBE0D5"'
    out, at = [], 0
    for a, b in merged:
        out.append(esc(s[at:a]))
        out.append("<span%s>%s</span>" % (mark, esc(s[a:b])))
        at = b
    out.append(esc(s[at:]))
    size_, lang_, bold = l.cicada_format
    l.set_markup('<span size="%d" lang="%s"%s>%s</span>' % (round(size_ * 768), lang_, ' weight="bold"' if bold else "", "".join(out)))
    return l


def fixed(line, size: int = 13, cls: str = "ink", terms: list = (), current: bool = False, lang: str | None = None) -> Gtk.Label:
    """A line as shown (改正听错的词): each fixed word underlined in grey (the Mac's dotted underline;
    Pango has no dotted one), a word waiting for the user on a pale wash. While searching, the search
    marks instead."""
    from ..core.correction import apply
    if terms or not line.fixes:
        return marked(line.shown, list(terms), size, cls, current, lang=lang or line.srcLang)
    s, marks = apply(line.fixes, line.src)
    asks = []
    for f in line.fixes:
        if f.ask is True:
            i = s.find(f.from_)
            if i >= 0:
                asks.append((i, i + len(f.from_)))
    spans = sorted([(a, b, ' underline="single" underline_color="#9EA2AC"') for a, b in marks]
                   + [(a, b, ' background="#FBE0D5"') for a, b in asks])
    out, at = [], 0
    for a, b, attr in spans:
        if a < at:
            continue
        out.append(esc(s[at:a]))
        out.append("<span%s>%s</span>" % (attr, esc(s[a:b])))
        at = b
    out.append(esc(s[at:]))
    l = text(s, size, cls, lang=lang or line.srcLang)
    size_, lang_, bold = l.cicada_format
    l.set_markup('<span size="%d" lang="%s"%s>%s</span>' % (round(size_ * 768), lang_, ' weight="bold"' if bold else "", "".join(out)))
    return l


def fixed_words(items, on_revert) -> Gtk.Widget:
    """Under a line: each fixed word, what it was heard as, and 改回. `items`: [(line id, fix)]."""
    from ..core.correction import label
    w = Wrap(6)
    for line_id, f in items:
        cf, ct = label(f)
        row = hbox(6)
        lab = Gtk.Label()
        lab.set_markup('<span size="%d"><span foreground="#6B7080">%s</span> %s <span foreground="#6B7080">→</span> %s</span>'
                       % (11 * 768, esc(L("听成")), esc(cf), esc(ct)))
        classes(lab, "ink")
        row.pack_start(lab, False, False, 0)
        b = Gtk.Button(label=L("改回"))
        classes(b, "fixlink")
        b.set_can_focus(False)  # the notes window never takes focus
        b.connect("clicked", lambda *_a, i=line_id, f=f: on_revert(i, f))
        row.pack_start(b, False, False, 0)
        w.add(panel(pad(row, 3, 8), "fixchip"))
    return w


def soft_button(label: str, on_click, dark: bool = False) -> Gtk.Button:
    """The Mac's SoftButton: dark for the answer, soft grey for the rest. Never takes focus."""
    b = Gtk.Button(label=label)
    classes(b, "darkbtn" if dark else "softbtn")
    b.set_can_focus(False)
    b.connect("clicked", lambda *_: on_click())
    return b


def fix_toast(fixes, message: str) -> Gtk.Widget:
    """The last fix decision said back (the Mac's FixToast): dark, with 撤销 while there is something
    to undo. Shown in place, not as an overlay: the notes window lays out top to bottom."""
    row = hbox(14)
    row.pack_start(text(message, 13, "", wrap=False), True, True, 0)
    if fixes.can_undo:
        b = Gtk.Button(label=L("撤销"))
        classes(b, "undo")
        b.set_can_focus(False)
        b.connect("clicked", lambda *_: fixes.undo())
        row.pack_start(b, False, False, 0)
    box = panel(pad(row, 5, 6, 5, 14), "toast")
    box.set_halign(Gtk.Align.CENTER)
    return box


def helper(s: str) -> Gtk.Label:
    return text(s, 11, "tertiary")


def heading(s: str, size: int = 16) -> Gtk.Label:
    return text(s, size, "heading", bold=True)


def esc(s: str) -> str:
    return GLib.markup_escape_text(s)


def icon(name: str, px: int = 16) -> Gtk.Image:
    img = Gtk.Image.new_from_icon_name(name, Gtk.IconSize.BUTTON)
    img.set_pixel_size(px)
    return img


def button(label: str, on_click, style: str = "outline", icon_name: str | None = None) -> Gtk.Button:
    b = Gtk.Button()
    if icon_name:
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.pack_start(icon(icon_name, 16), False, False, 0)
        box.pack_start(Gtk.Label(label=label), False, False, 0)
        box.set_halign(Gtk.Align.CENTER)
        b.add(box)
    else:
        b.set_label(label)
    for s in style.split():
        classes(b, s)
    b.connect("clicked", lambda *_: on_click())
    return b


def icon_button(icon_name: str, tooltip: str, on_click, extra: str = "", px: int = 15, focus: bool = True) -> Gtk.Button:
    b = Gtk.Button()
    b.add(icon(icon_name, px))
    b.set_tooltip_text(tooltip)
    b.get_accessible().set_name(tooltip)
    classes(b, "iconbtn", extra)
    b.set_can_focus(focus)
    b.connect("clicked", lambda *_: on_click())
    return b


def link(label: str, on_click) -> Gtk.Button:
    """A text action inside a sentence: rendered as a flat link-coloured button."""
    b = Gtk.Button(label=label)
    classes(b, "quietbtn")
    b.set_relief(Gtk.ReliefStyle.NONE)
    b.connect("clicked", lambda *_: on_click())
    return b


def status_line(tone: str, s: str, action: str | None = None, on_action=None) -> Gtk.EventBox:
    """A service in trouble, said the same way wherever it shows (the Mac's StatusLine): a dot, what
    waits for what · what still works, and at most one action. Colour sits in the dot only, so a
    passing wait doesn't read as a fault: "waiting" (yellow) comes back by itself, "needsyou" (red)
    needs the user, "info" (grey) is just so they know."""
    row = hbox(8)
    d = Gtk.Box()
    d.set_size_request(6, 6)
    d.set_valign(Gtk.Align.CENTER)
    d.set_halign(Gtk.Align.CENTER)
    classes(d, "statusdot", tone)
    row.pack_start(d, False, False, 0)
    label = text(s, 12, "secondary", width_chars=24)
    label.set_valign(Gtk.Align.CENTER)
    row.pack_start(label, True, True, 0)
    if action:
        b = Gtk.Button()
        b.add(text(action, 12, "ink", bold=True, wrap=False, ellipsize=False))
        classes(b, "quietbtn", "statusaction")
        b.set_relief(Gtk.ReliefStyle.NONE)
        b.set_can_focus(False)  # the notes window never takes focus
        b.set_valign(Gtk.Align.CENTER)
        b.connect("clicked", lambda *_: on_action())
        row.pack_end(b, False, False, 0)
    return panel(pad(row, 7, 12), "statusline")


def dot(live: bool) -> Gtk.Widget:
    d = Gtk.Box()
    d.set_size_request(9, 9)
    d.set_valign(Gtk.Align.CENTER)
    classes(d, "livedot" if live else "idledot")
    return d


def vbox(spacing: int = 0, *children) -> Gtk.Box:
    b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=spacing)
    for c in children:
        b.pack_start(c, False, False, 0)
    return b


def hbox(spacing: int = 0, *children) -> Gtk.Box:
    b = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=spacing)
    for c in children:
        b.pack_start(c, False, False, 0)
    return b


def pad(widget, top: int, right: int | None = None, bottom: int | None = None, left: int | None = None):
    right = top if right is None else right
    bottom = top if bottom is None else bottom
    left = right if left is None else left
    widget.set_margin_top(top)
    widget.set_margin_end(right)
    widget.set_margin_bottom(bottom)
    widget.set_margin_start(left)
    return widget


def gap(widget, top: int):
    widget.set_margin_top(top)
    return widget


def clear(box: Gtk.Container) -> None:
    for c in box.get_children():
        box.remove(c)
        c.destroy()


def panel(widget, *cls) -> Gtk.EventBox:
    """A styled container (GTK 3 boxes don't draw backgrounds; an EventBox does)."""
    e = Gtk.EventBox()
    e.add(widget)
    classes(e, *cls)
    return e


def segmented(options, current, on_change) -> Gtk.Box:
    """Two or three linked toggles, one checked: GNOME's view switcher in miniature."""
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
    classes(box, "segmented")
    buttons = {}
    lock = {"busy": False}

    def toggled(btn, value):
        if lock["busy"]:
            return
        lock["busy"] = True
        for v, b in buttons.items():
            b.set_active(v == value)
        lock["busy"] = False
        on_change(value)
    for value, label in options:
        b = Gtk.ToggleButton(label=label)
        b.set_active(value == current)
        b.connect("toggled", toggled, value)
        buttons[value] = b
        box.pack_start(b, False, False, 0)
    return box


def boxed(rows) -> Gtk.Widget:
    """A boxed list: rows separated by hairlines inside one rounded white card."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    for i, r in enumerate(rows):
        if i:
            classes(r, "prow-top")
        box.pack_start(r, False, False, 0)
    return panel(box, "boxed")


def prow(title: str, control: Gtk.Widget | None = None, subtitle: str | None = None, title_widget=None,
         subtitle_widget=None) -> Gtk.Widget:
    """One preferences row: title (and a grey subtitle) on the left, its control on the right.
    `subtitle_widget`: a grey line the caller rewrites later, in place of `subtitle`."""
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
    left.set_valign(Gtk.Align.CENTER)
    left.pack_start(title_widget or text(title, 13, "ink", wrap=False, ellipsize=False), False, False, 0)
    if subtitle_widget is not None:
        left.pack_start(subtitle_widget, False, False, 0)
    elif subtitle:
        left.pack_start(text(subtitle, 11, "tertiary", width_chars=50), False, False, 0)
    row.pack_start(left, True, True, 0)
    if control is not None:
        control.set_valign(Gtk.Align.CENTER)
        row.pack_end(control, False, False, 0)
    return panel(pad(row, 10, 14), "prow")


def icon_tile(icon_name: str, size: int = 64, glyph: int = 30, tone: str = "") -> Gtk.Widget:
    img = icon(icon_name, glyph)
    img.set_halign(Gtk.Align.CENTER)
    img.set_valign(Gtk.Align.CENTER)
    t = panel(img, "icon-tile", tone)
    t.set_size_request(size, size)
    t.set_halign(Gtk.Align.CENTER)
    t.set_valign(Gtk.Align.CENTER)
    return t


def breathing_dot(small: bool = False) -> Gtk.Widget:
    """BreathingDot: an accent dot with a ring swelling out of it ("live", without blinking).
    small: the Mac's 6 px one (the records list)."""
    d = dot(True)
    if small:
        d.set_size_request(6, 6)
        classes(d, "small")
    classes(d, "breathing")
    return d


def ring_pixbuf(fraction: float, px: int = 26, track: str = "#3A3D45", color: str = "#E8552B"):
    """The countdown ring around the logo (ListenPill's ending state), as an SVG: Ubuntu ships the SVG
    pixbuf loader but not the cairo bindings a drawn widget would need."""
    from gi.repository import GdkPixbuf
    r = 11.75
    c = 2 * math.pi * r
    f = max(0.0, min(1.0, fraction))
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 26 26">'
           '<circle cx="13" cy="13" r="%.2f" fill="none" stroke="%s" stroke-width="2.5"/>'
           '<circle cx="13" cy="13" r="%.2f" fill="none" stroke="%s" stroke-width="2.5" stroke-linecap="round"'
           ' stroke-dasharray="%.2f %.2f" transform="rotate(-90 13 13)"%s/></svg>'
           % (px, px, r, track, r, color, c * f, c, "" if f > 0 else ' stroke-opacity="0"'))
    loader = GdkPixbuf.PixbufLoader.new_with_type("svg")
    loader.write(svg.encode())
    loader.close()
    return loader.get_pixbuf()


def place_tag(line) -> Gtk.Widget:
    """现场 / 线上 beside the other side's label in a meeting that heard both (the Mac's PlaceTag): filled
    for the room microphone, outlined for the computer's audio."""
    room = line.via == "room"
    l = text(L("现场") if room else L("线上"), 10, "", wrap=False, ellipsize=False)
    pad(l, 0, 5)  # a margin: GTK 3 ignores CSS padding on an EventBox
    c = panel(l, "placetag", *(["room"] if room else []))
    c.set_valign(Gtk.Align.CENTER)
    c.set_tooltip_text(L("会议室的麦克风听到的") if room else L("电脑里放出来的"))
    return c


def me_tag() -> Gtk.Widget:
    """My own line (the Mac's MeTag): said through 同声传译, so what the other side heard was its
    translation. 你 in the accent, then an outlined 同传 pill."""
    pill = text(L("同传"), 10, "", wrap=False, ellipsize=False)
    pad(pill, 1, 5)  # a margin: GTK 3 ignores CSS padding on an EventBox
    p = panel(pill, "metag")
    p.set_valign(Gtk.Align.CENTER)
    box = hbox(5)
    box.set_halign(Gtk.Align.START)  # the tooltip covers the tag, not the row
    box.pack_start(text(L("你"), 11, "accent", bold=True, wrap=False, ellipsize=False), False, False, 0)
    box.pack_start(p, False, False, 0)
    # Linux turns it on and off (开始说, the shortcut), it has no key to hold: not the Mac's tooltip.
    box.set_tooltip_text(L("同声传译时说的，对方听到的是译文"))
    return box


def chip(s: str, now: bool = False) -> Gtk.Widget:
    l = text(s, 11, "", bold=True, wrap=False, ellipsize=False)
    if now:
        pad(l, 1, 6)  # a margin: GTK 3 ignores CSS padding on an EventBox
    c = panel(l, "chip", "now" if now else "time")
    c.set_valign(Gtk.Align.BASELINE)
    return c


class _Fraction(Gtk.Bin):
    """Gives its child `fraction` of the width it is given (the Mac's GeometryReader), asking for none."""

    def __init__(self, child: Gtk.Widget, fraction: float):
        super().__init__()
        self.fraction = fraction
        self.add(child)

    def do_size_allocate(self, a):
        self.set_allocation(a)
        r = Gdk.Rectangle()
        r.x, r.y, r.width, r.height = a.x, a.y, max(1, int(a.width * self.fraction)), a.height
        self.get_child().size_allocate(r)


class Wrap(Gtk.Fixed):
    """The Mac's FlowLayout: children left to right at their natural size, wrapping onto the next
    line. (A FlowBox lines its children up in columns, which spreads a row of chips apart.)"""

    def __init__(self, spacing: int = 6):
        super().__init__()
        self.spacing = spacing

    def _lines(self, width: int):
        """[(row height, [(child, x, w, h)…])…] for this width."""
        lines, row, x, h = [], [], 0, 0
        for c in self.get_children():
            if not c.get_visible():
                continue
            w = c.get_preferred_width()[1]
            ch = c.get_preferred_height_for_width(w)[1]
            if row and x + w > width:
                lines.append((h, row))
                row, x, h = [], 0, 0
            row.append((c, x, w, ch))
            x += w + self.spacing
            h = max(h, ch)
        if row:
            lines.append((h, row))
        return lines

    def do_get_request_mode(self):
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH

    def do_get_preferred_width(self):
        ws = [c.get_preferred_width()[1] for c in self.get_children() if c.get_visible()]
        return max(ws, default=0), sum(ws) + self.spacing * max(0, len(ws) - 1)

    def do_get_preferred_height_for_width(self, width):
        lines = self._lines(width)
        h = sum(lh for lh, _ in lines) + self.spacing * max(0, len(lines) - 1)
        return h, h

    def do_get_preferred_height(self):
        return self.do_get_preferred_height_for_width(self.do_get_preferred_width()[1])

    def do_size_allocate(self, a):
        self.set_allocation(a)
        y = a.y
        for lh, row in self._lines(a.width):
            for c, x, w, h in row:
                r = Gdk.Rectangle()
                r.x, r.y, r.width, r.height = a.x + x, y + (lh - h) // 2, min(w, a.width), h
                c.size_allocate(r)
            y += lh + self.spacing


def skeleton(fraction: float = 1.0, height: int = 12) -> Gtk.Widget:
    """SkeletonBar: a placeholder line with a light sweeping across it (the .skeleton CSS)."""
    bar = Gtk.Box()
    bar.set_size_request(-1, height)
    classes(bar, "skeleton", "thin" if height < 10 else "")
    return _Fraction(bar, fraction)


def sound_bars() -> Gtk.Widget:
    """SoundBars: four small orange bars rising and falling, "listening" at the size of a line of text."""
    row = hbox(3)
    for i in range(4):
        b = Gtk.Box()
        classes(b, "soundbar", "b%d" % i if i else "")
        row.pack_start(b, False, False, 0)
    row.set_valign(Gtk.Align.CENTER)
    return row


class Toasts:
    """GNOME-style toast at the bottom of a window: one at a time, an optional action, gone after
    a few seconds (or when the next one comes). `on_timeout` runs when it expires unacted."""

    def __init__(self, overlay: Gtk.Overlay):
        self.revealer = Gtk.Revealer()
        self.revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_UP)
        self.revealer.set_halign(Gtk.Align.CENTER)
        self.revealer.set_valign(Gtk.Align.END)
        self.revealer.set_margin_bottom(24)
        overlay.add_overlay(self.revealer)
        self._timer = None
        self._expire = None

    def show(self, message: str, action: str | None = None, on_action=None, on_timeout=None, seconds: int = 5) -> None:
        self.dismiss(run_timeout=True)
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        row.pack_start(text(message, 13, "", wrap=False), False, False, 0)
        if action:
            def act(*_):
                self._expire = None
                self.dismiss(run_timeout=False)
                if on_action:
                    on_action()
            b = Gtk.Button(label=action)
            b.connect("clicked", act)
            row.pack_start(b, False, False, 0)
        box = panel(pad(row, 5, 5, 5, 14), "toast")
        for c in self.revealer.get_children():
            self.revealer.remove(c)
        self.revealer.add(box)
        box.show_all()
        self.revealer.set_reveal_child(True)
        self._expire = on_timeout
        self._timer = GLib.timeout_add_seconds(seconds, self._timed_out)

    def _timed_out(self):
        self._timer = None
        self.dismiss(run_timeout=True)
        return False

    def dismiss(self, run_timeout: bool = True) -> None:
        if self._timer is not None:
            GLib.source_remove(self._timer)
            self._timer = None
        expire, self._expire = self._expire, None
        self.revealer.set_reveal_child(False)
        if run_timeout and expire:
            expire()


def loudness(rms: float) -> float:
    """-50 dBFS (a quiet room) to 0 dBFS on a log scale, so speech sits mid-bar instead of pinning it."""
    return 0.0 if rms <= 0 else max(0.0, min(1.0, (20 * math.log10(rms) + 50) / 50))


def no_wheel(combo: Gtk.ComboBox, scroll: Gtk.ScrolledWindow) -> None:
    """A GTK 3 dropdown changes its value under the mouse wheel; scrolling a page past one would
    silently change (and save) a setting. The wheel scrolls the page instead."""
    def wheel(_w, event):
        adj = scroll.get_vadjustment()
        ok, _dx, dy = event.get_scroll_deltas()
        if not ok:
            dy = {Gdk.ScrollDirection.UP: -1, Gdk.ScrollDirection.DOWN: 1}.get(event.direction, 0)
        adj.set_value(adj.get_value() + dy * 60)
        return True
    combo.connect("scroll-event", wheel)
