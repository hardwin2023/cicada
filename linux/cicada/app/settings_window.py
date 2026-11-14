"""设置, GNOME preferences style: groups of boxed-list rows, the title and a grey line on the left and
the control on the right. AI 服务 (the service, its key, what works with it, its models), languages,
what shows while listening (and 登录时启动), 同声传译, 结束会议, about."""
from __future__ import annotations

import os
import subprocess
import threading
import time
import urllib.parse

from gi.repository import Gdk, GLib, Gtk, Pango

from .. import VERSION
from ..core import ling as lingmod
from ..core import voice_reference
from ..core import voices as voicemod
from ..core.ling import AIKey
from ..core.strings import L, LF
from ..core.support import TARGETS, Paths, follow_system_target, my_language, system_languages
from . import ui

LING_PLATFORM = "https://chat.ant-ling.com/platform/api"


def open_uri(uri: str) -> None:
    try:
        Gtk.show_uri_on_window(None, uri, Gtk.get_current_event_time())
    except GLib.Error:
        subprocess.Popen(["xdg-open", uri], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def choice(options, current, on_change) -> Gtk.ComboBoxText:
    c = Gtk.ComboBoxText()
    for value, label in options:
        c.append(value, label)
    c.set_active_id(current if current in [o[0] for o in options] else options[0][0])
    c.connect("changed", lambda w: on_change(w.get_active_id()))
    c.set_size_request(170, -1)
    return c


def target_options():
    """跟随系统（简体中文 / English）: my language, then what it becomes when they speak mine."""
    names = {code: name for name, code in TARGETS}
    prefs = system_languages()
    mine = my_language(prefs)
    both = " / ".join(names.get(c, c) for c in (mine, follow_system_target(mine, prefs)))
    return [("system", LF("跟随系统（%@）", both))] + [(code, name) for name, code in TARGETS]


# 登录时启动: an XDG autostart entry, the file's presence being the setting.

def autostart_path() -> str:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "autostart", "com.wquguru.cicada%s.desktop" % (".dev" if Paths.dev else ""))


def autostart_enabled() -> bool:
    return os.path.isfile(autostart_path())


def set_autostart(on: bool, launcher: str) -> None:
    path = autostart_path()
    if not on:
        try:
            os.remove(path)
        except OSError:
            pass
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # --background: a login start stays in the top bar; opening 知了 by hand shows its window.
    with open(path, "w", encoding="utf-8") as f:
        f.write("[Desktop Entry]\nType=Application\nName=Cicada\nName[zh_CN]=知了\n"
                "Exec=%s%s --background\nIcon=cicada\nTerminal=false\nNoDisplay=true\nX-GNOME-Autostart-enabled=true\n"
                % (launcher, " --dev" if Paths.dev else ""))


def refresh_autostart(launcher: str) -> None:
    """An autostart file from before --background (or from another install place) is rewritten."""
    path = autostart_path()
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return
    if "--background" not in text or ("Exec=%s " % launcher) not in text:
        set_autostart(True, launcher)


# GNOME custom keyboard shortcuts: `cicada --toggle` (开始 / 结束听) and `cicada --speak` (开始 / 停止说).

PREVIEW = {  # what 试听 says, spoken text not UI (not L()): one per language a voice speaks
    "en": "This is the voice the room will hear.", "zh": "这是对方会听到的声音。",
    "ja": "これは相手に聞こえる声です。", "ko": "상대방에게 들리는 목소리입니다.",
    "es": "Esta es la voz que oirán los demás.", "fr": "Voici la voix que les autres entendront.",
    "de": "So klingt die Stimme, die die anderen hören.",
}
SHORTCUTS = {"toggle": ("cicada", "<Super><Shift>c", "Super + Shift + C"),
             "speak": ("cicada-speak", "<Super><Shift>s", "Super + Shift + S")}
MEDIA_KEYS = "org.gnome.settings-daemon.plugins.media-keys"
CUSTOM = "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"


def _custom_path(which: str) -> str:
    return "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/%s%s/" % (SHORTCUTS[which][0], "-dev" if Paths.dev else "")


def gnome_shortcut(which: str):
    """None off GNOME; "" when not added; else the key, as shown."""
    try:
        from gi.repository import Gio
        source = Gio.SettingsSchemaSource.get_default()
        if not source or not source.lookup(MEDIA_KEYS, True):
            return None
        keys = Gio.Settings.new(MEDIA_KEYS)
        if _custom_path(which) not in keys.get_strv("custom-keybindings"):
            return ""
        return SHORTCUTS[which][2]
    except Exception:  # noqa: BLE001 - any failure: treat as not GNOME
        return None


def set_gnome_shortcut(which: str, command: str) -> None:
    from gi.repository import Gio
    keys = Gio.Settings.new(MEDIA_KEYS)
    paths = keys.get_strv("custom-keybindings")
    if _custom_path(which) not in paths:
        keys.set_strv("custom-keybindings", paths + [_custom_path(which)])
    one = Gio.Settings.new_with_path(CUSTOM, _custom_path(which))
    one.set_string("name", "Cicada" if which == "toggle" else "Cicada · 同声传译")
    one.set_string("command", command)
    one.set_string("binding", SHORTCUTS[which][1])


class SettingsWindow(Gtk.Window):
    def __init__(self, app):
        super().__init__(title=L("设置") + " · " + L("知了"))
        self.app = app
        self.set_default_size(640, 760)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_wmclass("cicada", "Cicada")
        self.connect("delete-event", lambda *_: self.hide() or True)
        self.connect("key-press-event", lambda _w, e: (self.hide() or True) if e.keyval == Gdk.KEY_Escape else False)
        bar = Gtk.HeaderBar()
        bar.set_show_close_button(True)
        bar.set_title(L("设置"))
        ui.classes(bar, "cicada", "ground-bar")
        self.set_titlebar(bar)
        s = app.settings

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        ui.classes(scroll, "ground")
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)
        ui.pad(page, 8, 32, 28, 32)
        scroll.add(page)
        self.add(scroll)
        self.scroll = scroll

        def save():
            s.save()
            app.settings_changed()

        # AI 服务: the service and its key, what works with it, and its models (AISettings.swift).
        self._ai_section(page)

        # Languages
        def set_target(v):
            s.target = v
            save()

        def set_notes(v):
            app.listen.set_notes_language(v)  # saves, and rewrites the live meeting's notes in it

        def set_ui(v):
            s.uiLanguage = v
            save()
        names = {code: name for name, code in TARGETS}
        heard = app.listen.meeting_language(app.listen.session_id) if app.listen.listening else None
        notes_options = [("mine", LF("我的语言 · %@", names.get(s.target_code, s.target_code))),
                         ("source", LF("会议原文 · %@", names.get(heard, heard)) if heard else L("会议原文"))]
        combos = [choice(target_options(), s.target, set_target),
                  ui.segmented(notes_options, s.notesLanguage, set_notes),
                  choice([("system", L("跟随系统")), ("zh-Hans", "简体中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어")],
                         s.uiLanguage, set_ui)]
        ui_row = ui.prow(L("界面语言"), combos[2], L("重启知了后生效"))
        page.pack_start(self._group(L("语言"), ui.boxed([ui.prow(L("翻译成"), combos[0]), ui.prow(L("纪要语言"), combos[1], L("实时纪要和完整版同一种语言")), ui_row])),
                        False, False, 0)

        # 词表 (改正听错的词), after 语言 as on the Mac.
        from .word_list import WordList
        self.word_list = WordList(app, self._group)
        self.word_list_group = self.word_list.widget
        page.pack_start(self.word_list_group, False, False, 0)

        # While listening
        switch = Gtk.Switch()
        switch.set_active(autostart_enabled())
        switch.connect("notify::active", lambda w, _p: set_autostart(w.get_active(), app.launcher))
        dock = Gtk.Switch()
        dock.set_active(s.showInDock)
        dock.connect("notify::active", lambda w, _p: app.set_show_in_dock(w.get_active()))
        warn = ui.hbox(12)
        warn_icon = ui.icon("view-reveal-symbolic", 15)
        ui.classes(warn_icon, "warn")
        warn_icon.set_valign(Gtk.Align.START)
        warn.pack_start(warn_icon, False, False, 0)
        warn.pack_start(ui.text(L("Linux 下共享屏幕时对方能看到纪要窗。共享前点它右上角的 × 隐藏，知了会继续听。"), 12, "", width_chars=50), True, True, 0)
        warn_row = ui.panel(ui.pad(warn, 10, 14), "warnrow")
        page.pack_start(self._group(L("正在听时"), ui.boxed([
            ui.prow(L("悬浮窗"), ui.segmented([("notes", L("实时纪要")), ("subtitles", L("字幕条"))], s.view, app.set_view)),
            ui.prow(L("登录时打开"), switch, L("登录后在顶栏待命")),
            ui.prow(L("在 Dock 中显示"), dock, L("关掉后只在顶栏，打开窗口时才出现")),
            self._shortcut_row(),
            warn_row])), False, False, 0)

        # 通用, the Mac's records section: what each meeting keeps.
        self.general = self._group(L("通用"), ui.boxed([self._record_row(), self._voices_row()]))
        page.pack_start(self.general, False, False, 0)
        # 会后存一份 (存到文件夹), under 通用 as on the Mac.
        from .folder_export_view import FolderExportCard
        self.folder_card = FolderExportCard(app, self._group, self)
        page.pack_start(self.folder_card.widget, False, False, 0)
        self.connect("show", lambda *_: app.folder_export.retry())  # a folder fixed meanwhile

        room_group, room_combos = self._room_group()
        page.pack_start(room_group, False, False, 0)
        combos += room_combos
        page.pack_start(self._speak_group(combos), False, False, 0)
        page.pack_start(self._end_group(), False, False, 0)

        # About
        # 版本 with the update check under it and its button (UpdateViews' settings row).
        self.version_slot = ui.hbox(0)
        self.version_row = ui.prow(LF("版本 %@", VERSION + " · Linux"), self.version_slot, " ")
        rows = [self.version_row]
        for label, action in ((L("打开记录文件夹"), lambda: self._open_folder(Paths.sessions())),
                              (L("打开日志"), lambda: open_uri("file://" + Paths.log())),
                              (L("新手引导"), app.show_onboarding)):
            b = Gtk.Button()
            inner = ui.hbox(8, ui.text(label, 13, "ink", wrap=False))
            chevron = ui.icon("go-next-symbolic", 12)
            ui.classes(chevron, "tertiary")
            inner.pack_end(chevron, False, False, 0)
            b.add(ui.pad(inner, 10, 14))
            ui.classes(b, "linkrow")
            b.connect("clicked", lambda _b, a=action: a())
            rows.append(b)
        page.pack_start(self._group(L("关于"), ui.boxed(rows)), False, False, 0)

        for c in combos:
            ui.no_wheel(c, scroll)
        app.ling.on_change(lambda: GLib.idle_add(self.show_key_state))
        self.ai_shown = None
        self.connect("show", lambda *_: self.show_key_state())
        self.refresh_version()

    def refresh_version(self) -> None:
        """The update line and button: 检查更新, 安装并重新打开 / 重试, nothing while downloading."""
        u = self.app.updates
        detail = u.detail()
        sub = next((w for w in _labels(self.version_row) if w.get_style_context().has_class("secondary")
                    or w.get_style_context().has_class("tertiary")), None)
        if sub is not None:
            ui.retext(sub, detail or " ")
            ui.classes(sub, "err") if u.failure and u.update else sub.get_style_context().remove_class("err")
            # The release page's address, when no browser opened: copyable.
            sub.set_selectable(bool(u.failure and u.update and not u.opened))
        key = (u.update is not None, u.progress is not None, bool(u.failure), u.check == "checking", u.after_meeting)
        if key == getattr(self, "_version_key", None):
            return
        self._version_key = key
        ui.clear(self.version_slot)
        if u.update is not None and u.progress is None:
            if u.after_meeting:
                return
            b = ui.button(L("重试") if u.failure else L("安装并重新打开"), u.install, "outline" if u.failure else "darkbtn")
        elif u.update is None:
            b = ui.button(L("检查更新"), u.check_now, "outline")
            b.set_sensitive(u.check != "checking")
        else:
            return
        b.set_valign(Gtk.Align.CENTER)
        self.version_slot.pack_start(b, False, False, 0)
        self.version_slot.show_all()

    def _end_group(self) -> Gtk.Widget:
        """结束会议: when a meeting ends by itself (meeting_end.py), as the Mac's settings say it."""
        s = self.app.settings

        def save():
            s.save()
            self.app.settings_changed()
        app_switch = Gtk.Switch()
        app_switch.set_active(s.endWithApp)
        app_switch.connect("notify::active", lambda w, _p: (setattr(s, "endWithApp", w.get_active()), save()))
        minutes = ui.prow(L("多久算没人说话"), ui.segmented([(str(m), LF("%lld 分钟", m)) for m in (5, 10, 15, 30)],
                                                       str(s.silenceMinutes),
                                                       lambda v: (setattr(s, "silenceMinutes", int(v)), save())))
        # Hidden after the window's show_all() (a no_show_all row would stay empty once shown).
        self.connect("show", lambda *_: minutes.set_visible(s.silenceEnd != "off"))

        def set_silence(v):
            s.silenceEnd = v
            save()
            minutes.set_visible(v != "off")
        silence = ui.prow(L("没人说话时"), ui.segmented([("prompt", L("提醒后结束")), ("end", L("直接结束")), ("off", L("一直记录"))],
                                                    s.silenceEnd, set_silence), L("按识别出的话算，背景音乐不算"))
        return self._group(L("结束会议"), ui.boxed([
            ui.prow(L("会议应用挂断后结束"), app_switch, L("Zoom、腾讯会议、飞书、Teams 等")), silence, minutes]))

    def _shortcut_row(self, which: str = "toggle") -> Gtk.Widget:
        """From anywhere: GNOME runs `cicada --toggle` / `--speak` on a custom keyboard shortcut.
        Added only when the user asks (it writes to their keyboard settings)."""
        title = L("开始 / 结束听的快捷键") if which == "toggle" else L("开始 / 停止说的快捷键")
        flag = " --toggle" if which == "toggle" else " --speak"
        state = gnome_shortcut(which)
        if state is None:  # not GNOME: say how
            return ui.prow(title, None, LF("在系统的键盘设置里，把命令 %@ 绑到一个按键", self.app.launcher + flag))
        label = ui.text(state or "", 12, "secondary", wrap=False)

        def add():
            set_gnome_shortcut(which, self.app.launcher + (" --dev" if Paths.dev else "") + flag)
            ui.retext(label, SHORTCUTS[which][2])
            button.set_visible(False)
        button = ui.button(L("添加"), add, "outline")
        box = ui.hbox(8, label, button)
        if state:
            button.set_visible(False)
            button.set_no_show_all(True)
        return ui.prow(title, box, L("在任何窗口里都能用"))

    def _record_row(self) -> Gtk.Widget:
        """保存会议录音: on by default, as on the Mac; greyed out, saying why, without an AAC encoder.
        Checked again each time Settings shows: the formats may have been installed meanwhile."""
        app = self.app
        sw = Gtk.Switch()
        sw.set_valign(Gtk.Align.CENTER)
        hint = ui.text("", 11, "tertiary", width_chars=50)
        state = {"ok": False}

        def check(*_):
            from . import media
            media.rescan()
            ok = state["ok"] = app.can_record
            sw.set_active(ok and app.settings.recordAudio)
            sw.set_sensitive(ok)
            ui.retext(hint, L("只存在这台电脑上") if ok else L("这台电脑缺少 AAC 编码器，装上“第三方媒体格式”后可用"))

        def toggled(w, _p):
            if not state["ok"]:
                return
            app.settings.recordAudio = w.get_active()
            app.settings.save()
            app.settings_changed()
        check()
        sw.connect("notify::active", toggled)
        self.connect("show", check)
        return ui.prow(L("保存会议录音"), sw, subtitle_widget=hint)

    def scroll_to_general(self) -> None:
        """Brings 通用 into view (the records window's 保存会议录音 link), once it is laid out."""
        def go():
            # In the page's own coordinates (the viewport's are shifted by the current scroll).
            pos = self.general.translate_coordinates(self.scroll.get_child().get_child(), 0, 0)
            if pos is not None:
                self.scroll.get_vadjustment().set_value(max(0, pos[1] - 8))
            return False
        # A window just shown isn't laid out yet, and its show handlers then hide rows above 通用: once
        # it has a size, and again once those are gone.
        GLib.timeout_add(150, go)
        GLib.timeout_add(500, go)

    def _voices_row(self) -> Gtk.Widget:
        """说话人识别: on by default, as on the Mac; off when this build has no voiceprint library."""
        app = self.app
        sw = Gtk.Switch()
        sw.set_valign(Gtk.Align.CENTER)
        ok = app.voices_available
        sw.set_active(ok and app.settings.speakerVoices)
        sw.set_sensitive(ok)
        sw.connect("notify::active", lambda w, _p: app.set_speaker_voices(w.get_active()))
        return ui.prow(L("说话人识别"), sw, L("按声音标出说话人 1、2…，只在这台电脑上处理") if ok
                       else L("这个版本缺少声纹组件，暂时用不了"))

    def _speak_group(self, combos) -> Gtk.Widget:
        """同声传译: on/off (makes 知了 麦克风), my language, what they hear, the voice, 试听, the shortcut."""
        from ..core import voices as voicemod
        from ..core.support import TARGETS
        app, s = self.app, self.app.settings
        names = {c: n for n, c in TARGETS}
        rows = []
        switch = Gtk.Switch()
        switch.set_active(s.speakEnabled)
        dependents = []

        def toggled(w, _p):
            on = w.get_active()
            if on != s.speakEnabled and not app.set_speak_enabled(on):
                w.set_active(False)
                self.speak_status.set_visible(True)
                ui.retext(self.speak_status, L("没能建好知了麦克风"))
            for d in dependents:
                d.set_sensitive(s.speakEnabled)
        switch.connect("notify::active", toggled)
        rows.append(ui.prow(L("同声传译"), switch, L("你说的话翻译后，用“知了 麦克风”传给线上的人")))

        def set_from(v):
            s.speakFrom = v
            s.save()

        def set_to(v):
            s.speakTo = v
            s.save()
            fill_voices()
        mine = choice([("system", LF("和字幕一样（%@）", names.get(s.target_code, s.target_code)))] + [(c, n) for n, c in TARGETS],
                      s.speakFrom, set_from)
        theirs = choice([("room", LF("跟随对方（%@）", names.get(app.speak.target, app.speak.target)))] +
                        [(c, names.get(c, c)) for c in voicemod.ROOM_LANGUAGES], s.speakTo, set_to)
        voice = Gtk.ComboBoxText()
        voice.set_size_request(170, -1)
        # 我自己的声音, under 声音: redrawn with the voices (a new recording, another service).
        clone_slot = Gtk.EventBox()

        def fill_clone():
            ui.clear(clone_slot)
            clone_slot.add(self._clone_row())
            clone_slot.show_all()

        def fill_voices():
            code = app.speak.target
            voice.handler_block_by_func(set_voice) if getattr(voice, "_wired", False) else None
            voice.remove_all()
            for v, n, tags in voicemod.voices(code, app.ling.config()):
                voice.append(v, "%s · %s" % (n, "、".join(L(t) for t in tags)))
            if voice_reference.exists() and app.ling.usable and voicemod.clones(app.ling.config()):
                voice.append(voicemod.CLONE, L("我自己的声音"))
            voice.set_active_id(app.speak.voice(code) or "")
            if getattr(voice, "_wired", False):
                voice.handler_unblock_by_func(set_voice)
            fill_clone()

        def set_voice(w):
            v = w.get_active_id()
            if v:
                s.speakVoices[voicemod.key(app.speak.target)] = v
                s.save()
                fill_clone()
        fill_voices()
        voice.connect("changed", set_voice)
        voice._wired = True
        self._fill_voices = fill_voices  # again when the AI service (and so its voices) changes

        def preview():
            code = app.speak.target
            # In the voice's own language: a Japanese voice reading English says nothing about it.
            text = PREVIEW.get(code[:2], PREVIEW["en"]) if code != "zh-TW" else "這是對方會聽到的聲音。"
            from .room import Player

            def run():
                from ..core.support import Log
                p = Player(None)  # the speakers, not the room
                start, n = time.monotonic(), 0
                try:
                    for pcm in app.speak.speech(text, code, voice=app.speak.voice(code) or "US_Emma"):
                        n += len(pcm)
                        p.write(pcm)
                    p.drain()
                    Log.d("speak: preview %s %.1f s of voice in %.1f s" % (code, n / 2 / 24000, time.monotonic() - start))
                except Exception as e:  # noqa: BLE001
                    Log.d("speak: preview failed %s" % type(e).__name__)
                finally:
                    p.close()
            threading.Thread(target=run, daemon=True).start()
        self._preview_voice = preview
        voice_box = ui.hbox(8, voice, ui.button(L("试听"), preview, "outline"))
        self.voice_box = voice_box
        combos.extend([mine, theirs, voice])
        for title, control, sub in ((L("我说"), mine, None),
                                    (L("对方听到"), theirs, L("跟随对方时，对方说什么语言就翻成什么")),
                                    (L("声音"), voice_box, None)):
            r = ui.prow(title, control, sub)
            dependents.append(r)
            rows.append(r)
        dependents.append(clone_slot)
        rows.append(clone_slot)
        short = self._shortcut_row("speak")
        dependents.append(short)
        rows.append(short)
        # Without headphones a sentence said while they talk may be their voice from the speakers, so
        # it is dropped; with them it's mine, and talking over each other is normal in a meeting.
        phones = Gtk.Switch()
        phones.set_active(s.speakHeadphones)
        phones.set_valign(Gtk.Align.CENTER)

        def phones_toggled(sw, _p):
            self.app.set_headphones(sw.get_active())
        phones.connect("notify::active", phones_toggled)
        self.speak_phones = phones
        phones_row = ui.prow(L("戴着耳机"), phones, L("和对方同时说的话也会传出去"))
        dependents.append(phones_row)
        rows.append(phones_row)
        tip = ui.hbox(12)
        tip_icon = ui.icon("audio-headphones-symbolic", 15)
        ui.classes(tip_icon, "warn")
        tip_icon.set_valign(Gtk.Align.START)
        tip.pack_start(tip_icon, False, False, 0)
        tip.pack_start(ui.text(L("在会议软件里把麦克风选成“知了 麦克风”（或“默认”），并戴上耳机：外放时对方的声音会被当成你说的。"),
                               12, "", width_chars=50), True, True, 0)
        rows.append(ui.panel(ui.pad(tip, 10, 14), "warnrow"))
        for d in dependents:
            d.set_sensitive(s.speakEnabled)
        self.speak_status = ui.text("", 11, "warn", width_chars=60)
        self.speak_status.set_no_show_all(True)
        return ui.vbox(6, self._group(L("同声传译"), ui.boxed(rows)), ui.pad(self.speak_status, 0, 4, 0, 4))

    def _clone_row(self) -> Gtk.Widget:
        """我自己的声音 (VoicePicker.swift › cloneRow): 录制 until there is a recording, then how long
        it is and how it will sound, with 重录 / 删除. Only Ling clones: elsewhere it says so."""
        app, s = self.app, self.app.settings
        code = app.speak.target
        title = L("我自己的声音")
        if not voicemod.clones(app.ling.config()):
            return ui.prow(title, ui.soft_button(L("去换成 Ling"), lambda: app.show_settings(ai=True)), L("只有 Ling 能用你自己的声音"))
        if not voice_reference.exists():
            b = ui.soft_button(L("录制"), self.record_voice, dark=True)
            b.set_sensitive(app.ling.usable)
            return ui.prow(title, b, L("录 15 秒原声，对方听到你的音色，晚约 3 秒"))
        if voice_reference.saved_is_slow():
            note = L("读得偏慢")
        else:
            note = L("最像你") if voicemod.key(s.speak_from_code) == voicemod.key(code) else L("会带你的口音")
        controls = ui.hbox(8, ui.soft_button(L("重录"), self.record_voice), ui.soft_button(L("删除"), self.remove_voice))
        row = ui.prow(title, controls, LF("已录 %lld 秒 · %@", int(round(voice_reference.duration())), note))
        if app.speak.voice(code) == voicemod.CLONE:
            ui.classes(row, "voicewash")
        return row

    def record_voice(self) -> None:
        from .voice_clone import VoiceCloneDialog
        self.voice_dialog = VoiceCloneDialog(self.app, self, lambda saved: self._voice_done())

    def _voice_done(self) -> None:
        self.voice_dialog = None
        if hasattr(self, "_fill_voices"):
            self._fill_voices()

    def remove_voice(self) -> None:
        """The recording goes, and every language that used it is back on its default voice."""
        s = self.app.settings
        voice_reference.remove()
        s.speakVoices = {k: v for k, v in (s.speakVoices or {}).items() if v != voicemod.CLONE}
        s.save()
        if hasattr(self, "_fill_voices"):
            self._fill_voices()

    def _room_group(self):
        """会议室: the microphone 打开麦克风 hears the room with (自动 picks as roommic.pick does). Whether
        it hears the speakers is measured (roommic.EchoGate), not asked."""
        from ..core import roommic
        from . import capture
        app = self.app
        s = app.settings
        inputs = [i for i in roommic.parse_sources(capture.sources_text()) if not i.virtual]
        default = capture.default_source()
        if default == "cicada_mic":
            default = app.room.real_mic
        auto = roommic.pick(default, inputs)
        auto_name = next((i.description for i in inputs if i.name == auto), None)

        def set_mic(v):
            s.roomMic = v
            s.save()
        options = [("", LF("自动（%@）", auto_name) if auto_name else L("自动"))] + [(i.name, i.description) for i in inputs]
        if s.roomMic and all(v != s.roomMic for v, _ in options):
            options.append((s.roomMic, s.roomMic))  # chosen before, not plugged in now
        mic = choice(options, s.roomMic, set_mic)
        rows = [ui.prow(L("麦克风"), mic, L("戴着蓝牙耳机时，自动用电脑自带的麦克风"))]
        return self._group(L("会议室"), ui.boxed(rows)), [mic]

    def _group(self, title, body, footer=None) -> Gtk.Widget:
        box = ui.vbox(6, ui.pad(ui.text(title, 12, "group-title", bold=True, wrap=False), 0, 0, 0, 2), body)
        if footer:
            box.pack_start(ui.pad(ui.text(footer, 11, "tertiary", width_chars=60), 0, 2, 0, 2), False, False, 0)
        return box

    def _toggle_entry(self) -> None:
        self.entry_row.set_visible(not self.entry_row.get_visible())
        if self.entry_row.get_visible():
            self.key_entry.grab_focus()

    # AI 服务

    def _ai_section(self, page) -> None:
        """The service menu, its key (and a custom service's address), what works with it, and the
        models chosen for it. Rebuilt in parts by show_key_state as the service and its check change."""
        from ..core import providers
        app, s = self.app, self.app.settings
        self.provider_menu = choice([(p.id, "Ling" + L("（推荐）") if p.id == "ling" else L(p.name)) for p in providers.ALL],
                                    s.aiProvider, app.set_ai_provider)
        self.key_line = ui.text("", 13, "ink mono", wrap=False)
        self.key_status = ui.hbox(6)
        key_left = ui.vbox(4, self.key_line, self.key_status)
        self.change_button = ui.button(L("更换…"), self._toggle_entry, "outline")
        self.recheck_button = ui.button(L("重新检查"), app.recheck, "outline")
        self.remove_button = ui.button(L("删除"), self.remove_key, "dangertext")
        key_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        key_row.pack_start(key_left, True, True, 0)
        for b in (self.change_button, self.recheck_button, self.remove_button):
            b.set_valign(Gtk.Align.CENTER)
            key_row.pack_start(b, False, False, 0)
        key_row = ui.panel(ui.pad(key_row, 10, 14), "prow")
        self.key_entry = Gtk.Entry()
        self.key_entry.set_visibility(False)
        self.key_entry.set_placeholder_text("sk-…")
        self.key_entry.connect("activate", lambda *_: self.save_key())
        self.key_entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, "view-reveal-symbolic")
        self.key_entry.set_icon_tooltip_text(Gtk.EntryIconPosition.SECONDARY, L("显示 key"))
        self.key_entry.connect("icon-press", lambda e, *_: e.set_visibility(not e.get_visibility()))
        entry_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        entry_row.pack_start(self.key_entry, True, True, 0)
        entry_row.pack_start(ui.button(L("保存并检查"), self.save_key, "darkbtn"), False, False, 0)
        # A pasted key that belongs elsewhere (AISettings.swift › keyHint): what it is, 改用 <服务>.
        self.key_hint = ui.hbox(8)
        self.key_hint.set_no_show_all(True)  # no gap while empty
        self.entry_row = ui.panel(ui.pad(ui.vbox(8, entry_row, self.key_hint), 12, 16), "prow")
        # A custom service: one row per use instead of the key card (_custom_page).
        self.custom_page = self._custom_page()
        self.get_key = Gtk.Button()
        self.get_key_label = ui.text("", 13, "ink", wrap=False)
        self.get_key.add(ui.pad(ui.hbox(8, self.get_key_label), 10, 14))
        self.get_key.get_child().pack_end(ui.icon("external-link-symbolic", 14), False, False, 0)
        ui.classes(self.get_key, "linkrow")
        self.get_key.connect("clicked", lambda *_: open_uri(app.ling.provider.site or ""))
        self.get_key.set_no_show_all(True)
        self.get_key.get_child().show_all()
        # Shown and hidden by show_key_state; show_all() must leave them alone.
        self.entry_row.set_no_show_all(True)
        # Everything inside it (the hint stays out on its own): show_all() on the window stops at
        # entry_row, so a wrapper left hidden here kept the field from ever appearing.
        self.entry_row.get_child().show_all()
        self.key_group = ui.boxed([key_row, self.entry_row, self.get_key])
        title = ui.hbox(8, ui.pad(ui.text(L("AI 服务"), 12, "group-title", bold=True, wrap=False), 0, 0, 0, 2))
        title.pack_end(self.provider_menu, False, False, 0)
        self.lock_line = ui.text("", 11, "tertiary", width_chars=60)
        # The check, step by step, while something is wrong or being checked; OpenRouter's balance.
        self.steps = ui.vbox(0)
        self.steps_card = ui.panel(ui.pad(self.steps, 2, 14), "boxed")
        self.steps_card.set_no_show_all(True)
        self.balance_row = ui.hbox(8)
        self.balance_strip = ui.panel(ui.pad(self.balance_row, 10, 12), "warnstrip")
        self.balance_strip.set_no_show_all(True)
        page.pack_start(ui.vbox(6, title, self.custom_page, self.key_group, self.steps_card, self.balance_strip,
                                ui.pad(self.lock_line, 0, 2, 0, 2)), False, False, 0)
        # What works with it (a custom service says so in its own rows).
        self.uses = ui.vbox(0)
        self.uses_group = self._group(L("现在能用的"), self.uses)
        self.uses_group.set_no_show_all(True)
        for w in self.uses_group.get_children():  # show_all() stops at a no_show_all widget
            w.show_all()
        page.pack_start(self.uses_group, False, False, 0)
        # Its models, folded away: the recommended ones are already chosen.
        self.models = ui.vbox(0)
        self.models.set_no_show_all(True)
        fold = Gtk.Button()
        self.fold_label = ui.text(L("自己选模型") + " ›", 12, "secondary", wrap=False)
        fold.add(self.fold_label)
        ui.classes(fold, "linkrow")
        fold.set_halign(Gtk.Align.START)
        fold.connect("clicked", lambda *_: self._toggle_models())
        self.footnote = ui.text("", 11, "tertiary", width_chars=60)
        self.fold = fold
        fold.set_no_show_all(True)
        fold.get_child().show_all()
        page.pack_start(ui.vbox(6, fold, self.models, ui.pad(self.footnote, 0, 2, 0, 2)), False, False, 0)

    # 其他（兼容 OpenAI）: AISettings.swift › customPage, on a port

    def _custom_page(self) -> Gtk.Widget:
        """One row per use, each opening to its fields and how it's doing, each at its own address if
        need be (a text model, a speech model and an audio model often run as separate servers):
        翻译和纪要, 同传声音 and 听对方 (the hear model, which also hears what I say). The fields are
        built once; show_key_state only rewrites the headers and the status under them."""
        s = self.app.settings
        self.custom_open: set = set()
        self.custom_heads: dict = {}
        self.custom_bodies: dict = {}
        # 翻译和纪要
        self.custom_base = self._field("http://192.168.1.20:8000/v1", s.aiCustomBase)
        self.custom_base_bad = ui.text(L("地址要用 https；这台电脑和局域网里的服务可以用 http。"), 11, "stepwhy", width_chars=46)
        self.custom_base_bad.set_no_show_all(True)
        self.custom_base.connect("changed", lambda *_: self._custom_base_typed())
        # The models the service lists, once fetched; a name can always be typed.
        self.custom_text = ModelPicker(self._label(L("模型")), s.aiModels.get("custom", ""), L("例如 qwen3:14b"),
                                       self._custom_model_picked, lambda: self._refetch(False))
        self.custom_key_line = ui.text("", 13, "ink mono", wrap=False)
        self.custom_key = Gtk.Entry()
        self.custom_key.set_visibility(False)
        self.custom_key.set_width_chars(26)
        self.custom_key.connect("activate", lambda *_: self.save_key())
        self.custom_change = ui.button(L("更换"), self._custom_change_key, "outline")
        self.custom_remove = ui.button(L("移除 key"), self.remove_key, "dangertext")
        self.custom_save = ui.button(L("保存并检查"), self.save_key, "darkbtn")
        key_row = ui.hbox(8, self._label("key"), self.custom_key_line)
        # "Optional on this computer or your local network" doesn't fit 26 characters.
        key_row.pack_start(self.custom_key, True, True, 0)
        for b in (self.custom_change, self.custom_remove):
            b.set_valign(Gtk.Align.CENTER)
            key_row.pack_end(b, False, False, 0)
        self.custom_key_hint = ui.hbox(8)
        self.custom_key_hint.set_no_show_all(True)
        self.custom_text_status = ui.vbox(6)
        self.custom_editing = False
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        ui.classes(sep, "hairline")
        save_row = ui.hbox(8)
        save_row.pack_end(self.custom_save, False, False, 0)
        text_body = ui.vbox(8, self._subgroup(L("翻译")),
                            ui.hbox(8, self._label(L("地址")), self.custom_base), self.custom_base_bad,
                            key_row, self.custom_key_hint, self.custom_text.widget,
                            sep, self._notes_group(), save_row, self.custom_text_status)
        # 同传声音: Linux has no voice of its own to fall back on.
        self.custom_voice_model = self._field(L("例如 qwen3-tts"), s.aiVoiceModels.get("custom", ""))
        self.custom_voice = self._field(L("例如 vivian"), s.aiCustomVoice)
        self.custom_voice_base = self._field(L("跟上面一样"), s.aiCustomVoiceBase)
        voice_body = ui.vbox(8, ui.text(L("需支持 /audio/speech；不填则同声传译用不了"), 11, "tertiary", width_chars=50),
                             ui.hbox(8, self._label(L("模型")), self.custom_voice_model),
                             ui.hbox(8, self._label(L("声音")), self.custom_voice),
                             ui.hbox(8, self._label(L("地址")), self.custom_voice_base))
        # 听对方: the hear model, at the text model's address unless it has its own.
        self.custom_hear = self._field(L("例如 qwen3-omni"), s.aiHearModels.get("custom", ""))
        self.custom_hear_base = self._field(L("跟上面一样"), s.aiCustomHearBase)
        self.custom_hear_status = ui.vbox(4)
        hear_body = ui.vbox(8, ui.text(L("要能输入音频：听对方和“我说”都用它"), 11, "tertiary", width_chars=50),
                            ui.hbox(8, self._label(L("模型")), self.custom_hear),
                            ui.hbox(8, self._label(L("地址")), self.custom_hear_base), self.custom_hear_status)
        rows = []
        for sid, title, body in (("text", L("翻译和纪要"), text_body), ("voice", L("同传声音"), voice_body),
                                 ("hear", L("听对方"), hear_body)):
            rows.append(ui.vbox(0, self._custom_head(sid, title), self._custom_body(sid, body)))
        hint = ui.text(L("每样可以接不同的机器；这台电脑和局域网里的服务可以用 http。"), 12, "tertiary", width_chars=60)
        # 语音和文字只发给你的服务 (AISettings.swift › onlyRow): Google is never asked. The grey line says
        # what it costs, and while the service can't be reached, that new lines are the original only.
        self.only_switch = Gtk.Switch()
        self.only_switch.set_active(s.aiCustomOnly)
        self.only_switch.connect("notify::active", self._only_toggled)
        self.only_detail = ui.text(L("不用 Google 翻译；说话时要等整句说完才出译文"), 11, "tertiary", width_chars=50)
        only = ui.boxed([ui.prow(L("语音和文字只发给你的服务"), self.only_switch, subtitle_widget=self.only_detail)])
        page = ui.vbox(6, ui.pad(hint, 0, 2, 0, 2), ui.boxed(rows), only)
        page.set_no_show_all(True)
        for w in page.get_children():
            w.show_all()
        self.custom_base_bad.set_visible(False)
        self.custom_key_hint.set_visible(False)
        for body in self.custom_bodies.values():
            body.set_visible(False)
        return page

    # 纪要: AISettings.swift › notesGroup

    def _notes_group(self) -> Gtk.Widget:
        """The same service as translation (another model at most), or another one with its own
        address and key. Switching back keeps what was typed."""
        s = self.app.settings
        head = ui.hbox(8, self._subgroup(L("纪要")))
        head.pack_end(ui.segmented([("same", L("同一个服务")), ("own", L("另一个服务"))],
                                   "own" if s.aiCustomNotesOwn else "same", self._notes_own_picked), False, False, 0)
        self.notes_base = self._field(L("跟上面一样"), s.aiCustomNotesBase)
        self.notes_base_bad = ui.text(L("地址要用 https；这台电脑和局域网里的服务可以用 http。"), 11, "stepwhy", width_chars=46)
        self.notes_base_bad.set_no_show_all(True)
        self.notes_key_line = ui.text("", 13, "ink mono", wrap=False)
        self.notes_key = Gtk.Entry()
        self.notes_key.set_visibility(False)
        self.notes_key.set_width_chars(26)
        self.notes_key.set_placeholder_text(L("不填就用上面的 key"))
        self.notes_key.connect("activate", lambda *_: self.save_key())
        self.notes_change = ui.button(L("更换"), self._notes_change_key, "outline")
        self.notes_remove = ui.button(L("移除"), self._notes_remove_key, "dangertext")
        self.notes_editing = False
        key_row = ui.hbox(8, self._label("key"), self.notes_key_line)
        key_row.pack_start(self.notes_key, True, True, 0)
        for b in (self.notes_change, self.notes_remove):
            b.set_valign(Gtk.Align.CENTER)
            key_row.pack_end(b, False, False, 0)
        self.notes_own = ui.vbox(8, ui.hbox(8, self._label(L("地址")), self.notes_base), self.notes_base_bad, key_row)
        self.notes_own.set_no_show_all(True)
        for w in self.notes_own.get_children():
            w.show_all()
        self.notes_own.set_visible(s.aiCustomNotesOwn)
        self.notes_model = ModelPicker(self._label(L("模型")), s.aiModels.get("custom.notes", ""), L("和翻译模型一样"),
                                       self._notes_model_picked, lambda: self._refetch(True), same_label=L("和翻译模型一样"))
        # The grey helper, or why the notes' own model or server doesn't work.
        self.notes_line = ui.text("", 11, "tertiary", width_chars=46)
        return ui.vbox(8, head, self.notes_own, self.notes_model.widget,
                       ui.pad(self.notes_line, 0, 0, 0, 42))

    def _notes_own_picked(self, value: str) -> None:
        s = self.app.settings
        own = value == "own"
        if own == s.aiCustomNotesOwn:
            return
        s.aiCustomNotesOwn = own
        if own:
            s.aiCustomNotesBase = self.notes_base.get_text().strip()
        s.save()
        self.notes_own.set_visible(own)
        self.app.ai_changed()

    def _notes_model_picked(self, mid: str) -> None:
        self.save_key()

    def _notes_change_key(self) -> None:
        self.notes_editing = True
        self.notes_key.set_text("")
        self._show_notes_key()
        self.notes_key.grab_focus()

    def _notes_remove_key(self) -> None:
        """Notes go back to the translation key."""
        self.app.ling.notes_key_file.remove()
        self.notes_editing = False
        self.app.ai_changed()

    def _show_notes_key(self) -> None:
        ling = self.app.ling
        own = ling.notes_key_file.read() if ling.notes_has_own_key else None
        editing = not own or self.notes_editing
        self.notes_key_line.set_visible(not editing)
        ui.retext(self.notes_key_line, AIKey.masked(own) if own else "")
        self.notes_key.set_visible(editing)
        self.notes_change.set_visible(not editing)
        self.notes_remove.set_visible(not editing)
        n = ling.check_result.notes
        bad = n is not None and n.reason == lingmod.aicheck.INVALID_KEY
        (self.notes_key.get_style_context().add_class if bad else self.notes_key.get_style_context().remove_class)("error")

    def _refetch(self, notes: bool) -> None:
        """重新获取: the list of the address a model menu shows (the notes' own, or the service's)."""
        ling = self.app.ling
        c = ling.config()
        own = notes and c.notes_apart and c.for_notes.base != c.base
        threading.Thread(target=ling.fetch_notes_catalog if own else ling.fetch_catalog, daemon=True).start()

    @staticmethod
    def _subgroup(title: str) -> Gtk.Widget:
        """翻译 / 纪要 inside 翻译和纪要: 12 px semibold, ink."""
        return ui.text(title, 12, "ink", bold=True, wrap=False)

    def _check_rows(self, c, r) -> Gtk.Widget:
        """After a check with notes apart: one row each, what it runs and how it did."""
        from ..core import aicheck
        t, n = r.translate, r.notes
        if n is None:
            notes_text, notes_ok = "", True
        elif n.kind == aicheck.OK:
            notes_text, notes_ok = LF("能写纪要 · %@ 秒", "%.1f" % (n.seconds or 0)), True
        elif n.kind == aicheck.RUNNING:
            notes_text, notes_ok = L("正在检查…"), True
        elif n.reason in (aicheck.INVALID_KEY, aicheck.MGMT_KEY):
            notes_text, notes_ok = L("key 不对"), False
        else:
            notes_text, notes_ok = L("纪要写不了"), False

        def row(use, model, ok, result):
            dot = Gtk.Box()
            dot.set_valign(Gtk.Align.CENTER)
            ui.classes(dot, "statedot", "ok" if ok else "error")
            name = ui.text(use, 12, "ink", wrap=False, ellipsize=False)
            name.set_size_request(34, -1)
            m = ui.text(model, 12, "secondary mono", wrap=False)
            m.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
            line = ui.hbox(10, dot, name)
            line.pack_start(m, True, True, 0)
            line.pack_end(ui.text(result, 12, "ok" if ok else "stepwhy", wrap=False, ellipsize=False), False, False, 0)
            line.set_size_request(-1, 36)
            return ui.pad(line, 0, 12)
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        ui.classes(sep, "hairline")
        return ui.panel(ui.vbox(0, row(L("翻译"), c.text_model, True,
                                       LF("翻一句 %@ 秒", "%.1f" % t.seconds) + " · " + (L("会先思考") if t.thinks else L("不思考"))),
                                sep, row(L("纪要"), c.for_notes.text_model, notes_ok, notes_text)), "boxed")

    def _only_toggled(self, w, _p) -> None:
        if w.get_active() != self.app.settings.aiCustomOnly:
            self.app.set_custom_only(w.get_active())

    @staticmethod
    def _label(title: str) -> Gtk.Widget:
        l = ui.text(title, 12, "secondary", wrap=False, ellipsize=False)
        l.set_size_request(34, -1)
        l.set_xalign(0)
        return l

    def _custom_head(self, sid: str, title: str) -> Gtk.Widget:
        """A row that opens to its fields: a state dot, the use, what it runs on, and how it's doing."""
        dot = Gtk.Box()
        dot.set_valign(Gtk.Align.CENTER)
        ui.classes(dot, "statedot")
        detail = ui.text("", 11, "tertiary", wrap=False)
        trailing = ui.text("", 12, "tertiary", wrap=False, ellipsize=False)
        chevron = ui.icon("pan-end-symbolic", 12)
        left = ui.vbox(2, ui.text(title, 13, "ink", wrap=False), detail)
        # The middle takes the room left over and keeps its text at the start (not centred in it).
        row = ui.hbox(10, dot)
        row.pack_start(left, True, True, 0)
        row.pack_end(chevron, False, False, 0)
        row.pack_end(trailing, False, False, 0)
        b = Gtk.Button()
        b.add(ui.pad(row, 10, 14))
        ui.classes(b, "linkrow")
        b.connect("clicked", lambda *_: self._custom_toggle(sid))
        self.custom_heads[sid] = (dot, detail, trailing, chevron)
        return b

    def _custom_body(self, sid: str, body: Gtk.Widget) -> Gtk.Widget:
        box = ui.pad(body, 0, 16, 14, 32)
        self.custom_bodies[sid] = box
        return box

    def _custom_toggle(self, sid: str, on: bool | None = None) -> None:
        on = sid not in self.custom_open if on is None else on
        if on:
            self.custom_open.add(sid)
        else:
            self.custom_open.discard(sid)
        self.custom_bodies[sid].set_visible(on)
        self.custom_heads[sid][3].set_from_icon_name("pan-down-symbolic" if on else "pan-end-symbolic", Gtk.IconSize.MENU)

    def _custom_base_typed(self) -> None:
        from ..core import providers
        typed = self.custom_base.get_text().strip()
        self.custom_base_bad.set_visible(bool(typed) and providers.custom_base(typed) is None)
        self.custom_key.set_placeholder_text(L("本机和局域网服务可不填") if typed and providers.is_nearby(typed) else "sk-…")

    def _custom_model_picked(self, mid: str) -> None:
        """A model picked from the service's list (or typed, then Enter) saves and checks it."""
        self.save_key()

    def _custom_change_key(self) -> None:
        self.custom_editing = True
        self.custom_key.set_text("")
        self._show_custom_key()
        self.custom_key.grab_focus()

    def _show_custom_key(self) -> None:
        k = self.app.ling.current_key()
        editing = not k or self.custom_editing
        self.custom_key_line.set_visible(not editing)
        ui.retext(self.custom_key_line, AIKey.masked(k) if k else "")
        self.custom_key.set_visible(editing)
        self.custom_change.set_visible(not editing)
        self.custom_remove.set_visible(bool(k) and not editing)
        self.custom_save.set_visible(True)

    def _show_custom(self) -> None:
        """The custom rows' headers and status, from the settings and the last check."""
        from ..core import aicheck, providers
        from . import aicheck_view
        app = self.app
        ling = app.ling
        c = ling.config()
        s = app.settings
        r = ling.check_result
        f = r.failure
        have = ling.has_key
        self._custom_base_typed()
        self._show_custom_key()
        sens = not r.running
        self.custom_save.set_sensitive(sens)
        self.custom_save.set_label(L("正在检查…") if r.running else L("保存并检查"))
        # The model menus: what each address lists, once fetched.
        host = urllib.parse.urlsplit(c.base or "").hostname or ""
        self.custom_text.fill(ling.text_catalog, host)
        notes_elsewhere = c.notes_apart and c.for_notes.base != c.base
        notes_host = urllib.parse.urlsplit(c.for_notes.base or "").hostname or host
        self.notes_model.fill(ling.notes_catalog if notes_elsewhere else ling.text_catalog, notes_host)
        self.notes_base_bad.set_visible(s.aiCustomNotesOwn and c.notes_bad_address)
        self._show_notes_key()
        shared = not ling.notes_has_own_key
        why = r.notes_line(notes_host, c.for_notes.text_model, shared) if have else None
        for cls in ("stepwhy", "tertiary"):
            self.notes_line.get_style_context().remove_class(cls)
        self.notes_line.get_style_context().add_class("stepwhy" if why else "tertiary")
        # The Mac's sizes: 12 for the red line, 11 for the grey one (retext applies the size).
        self.notes_line.cicada_format = (12 if why else 11,) + tuple(self.notes_line.cicada_format[1:])
        ui.retext(self.notes_line, why or L("用来写实时纪要、识别说话人，默认和翻译用同一个"))
        self.notes_own.set_visible(s.aiCustomNotesOwn)  # a debug command may have switched it

        def head(sid, state, detail, trailing, tone=""):
            dot, d, t, _ = self.custom_heads[sid]
            for cls in ("ok", "warn", "error", "live"):
                dot.get_style_context().remove_class(cls)
            if state:
                dot.get_style_context().add_class(state)
            ui.retext(d, detail)
            ui.retext(t, trailing or "")
            for cls in ("warn", "stepwhy", "tertiary"):
                t.get_style_context().remove_class(cls)
            t.get_style_context().add_class(tone or "tertiary")

        # 翻译和纪要
        text_failed = f is not None and f[0] != "hear"
        notes_down = f is None and r.notes_failed
        if not have:
            state = ""
        elif r.running:
            state = "live"
        elif text_failed:
            state = "error"
        elif r.slow or r.busy or r.notes_failed:
            state = "warn"
        else:
            state = "ok" if r.passed or (f is not None and f[0] == "hear") else ""
        if r.running:
            trailing = L("正在检查…")
        elif text_failed and have:
            trailing = {"reach": L("暂时连不上"), "key": L("这个 key 用不了")}.get(f[0], L("模型用不了"))
        elif notes_down and have:
            trailing = L("纪要写不了")
        elif r.translate is not None:
            trailing = LF("翻一句 %@ 秒", "%.1f" % r.translate.seconds)
        else:
            trailing = None
        head("text", state, self._text_detail(c, host), trailing,
             "stepwhy" if have and (text_failed or notes_down) else "warn" if r.slow else "")
        ui.clear(self.custom_text_status)
        slow = r.slow_line(google_off=s.aiCustomOnly)  # this page is the custom service's
        if slow:
            self.custom_text_status.pack_start(ui.text(slow, 12, "warn", width_chars=46), False, False, 0)
        if have and aicheck_view.show_steps(r) and (text_failed or r.running or r.busy):
            card = ui.panel(ui.pad(aicheck_view.steps_widget(app, self._custom_change_key, recheck_in_step=False,
                                                             width_chars=40), 2, 12), "boxed")
            self.custom_text_status.pack_start(card, False, False, 0)
        elif (r.passed or (f is not None and f[0] == "hear")) and c.notes_apart and r.translate is not None:
            self.custom_text_status.pack_start(self._check_rows(c, r), False, False, 0)
        elif r.passed or (f is not None and f[0] == "hear"):
            facts = [L("能写纪要")]
            if r.translate is not None:
                facts.append(L("会先思考") if r.translate.thinks else L("不思考"))
            self.custom_text_status.pack_start(ui.text(" · ".join(facts), 11, "tertiary", wrap=False), False, False, 0)
        elif r.reason == aicheck.NO_JSON:
            self.custom_text_status.pack_start(ui.text(L("纪要写不了"), 11, "tertiary", wrap=False), False, False, 0)
        self.custom_text_status.show_all()
        # 同传声音
        voice = (s.aiVoiceModels.get("custom") or "").strip()
        vhost = urllib.parse.urlsplit(c.voice_base or "").hostname or host
        last = ling.last_voice
        head("voice", "" if not voice or last is None else "ok" if last[0] else "error",
             " · ".join(x for x in (vhost, voice, s.aiCustomVoice.strip()) if x) if voice else L("没填，同声传译用不了"),
             L("用不了") if not voice else (L("上次正常") if last[0] else L("上次没出声")) if last else None,
             "stepwhy" if last is not None and not last[0] and voice else "")
        # 听对方
        hear_st = r["hear"]
        hear_failed = f is not None and f[0] == "hear"
        hhost = ling.hear_host
        if not c.hear_model:
            hstate, htrail = "", None
        elif hear_failed:
            hstate, htrail = "error", L("暂时连不上") if f[1] == aicheck.UNREACHABLE else L("模型用不了")
        elif hear_st.kind == aicheck.OK:
            hstate = "ok"
            htrail = LF("%@ 秒", "%.1f" % hear_st.seconds) if hear_st.seconds is not None else None
        elif hear_st.kind == aicheck.BUSY_STATE:
            hstate, htrail = "warn", LF("%@ 现在很忙", ling.service_name)
        else:
            hstate, htrail = ("live", L("正在检查…")) if r.running else ("", None)
        head("hear", hstate if have else "", "%s · %s" % (hhost, c.hear_model) if c.hear_model and hhost
             else c.hear_model or L("填上听的模型"), htrail, "stepwhy" if hear_failed else "")
        ui.clear(self.custom_hear_status)
        if hear_failed and have:
            why = ling.message()
            if why:
                self.custom_hear_status.pack_start(ui.text(why, 12, "stepwhy", width_chars=46), False, False, 0)
        elif s.aiCustomHearBase.strip() and providers.custom_base(s.aiCustomHearBase) is None:
            self.custom_hear_status.pack_start(ui.text(L("地址要用 https；这台电脑和局域网里的服务可以用 http。"), 12, "stepwhy",
                                                       width_chars=46), False, False, 0)
        self.custom_hear_status.show_all()
        # 语音和文字只发给你的服务: set by a debug command too. Linux has no translation of its own to
        # stand in while the service can't be reached.
        on = s.aiCustomOnly
        if self.only_switch.get_active() != on:
            self.only_switch.set_active(on)  # _only_toggled sees it already saved
        down = on and have and not r.running and f is not None and f[1] != aicheck.BUSY
        ui.retext(self.only_detail, L("现在连不上：新字幕暂时只有原文") if down else L("不用 Google 翻译；说话时要等整句说完才出译文"))
        # A service that isn't set up yet, or doesn't work, opens where it needs filling in.
        if not getattr(self, "_custom_opened", False):
            self._custom_opened = True
            if not r.passed or r.slow:
                self._custom_toggle("text", True)

    @staticmethod
    def _text_detail(c, host: str) -> str:
        """"192.168.1.20 · qwen-mt-turbo", then the notes' model, or their own server after a bar."""
        if not host or not c.text_model:
            return L("填上地址和模型")
        line = "%s · %s" % (host, c.text_model)
        if not c.notes_apart:
            return line
        n = c.for_notes
        nhost = urllib.parse.urlsplit(n.base or "").hostname
        if nhost and n.base != c.base:
            return line + " ｜ %s · %s" % (nhost, n.text_model)
        return line if n.text_model == c.text_model else line + " · " + n.text_model

    def _field(self, placeholder: str, value: str) -> Gtk.Entry:
        e = Gtk.Entry()
        e.set_placeholder_text(placeholder)
        e.set_text(value)
        e.set_width_chars(26)
        e.connect("activate", lambda *_: self.save_key())
        return e

    def _toggle_models(self, on: bool | None = None) -> None:
        on = not self.models.get_visible() if on is None else on
        self.models.set_visible(on)
        if on:
            self.models.foreach(lambda w: w.show_all())
        ui.retext(self.fold_label, L("自己选模型") + (" ⌄" if on else " ›"))

    def _model_menu(self, kind: str, current: str, recommended, listed: list) -> Gtk.Widget:
        """Recommended models first, with why, then everything the service lists; a name can be typed."""
        c = Gtk.ComboBoxText.new_with_entry()
        seen = set()
        for m in recommended:
            c.append(m.id, m.id + ("  · " + L(m.note) if m.note else ""))
            seen.add(m.id)
        for mid in listed:
            if mid not in seen:
                c.append(mid, mid)
                seen.add(mid)
        if current not in seen:
            c.append(current, current)
        c.set_active_id(current)
        c.get_child().set_text(current)
        c.get_child().set_width_chars(26)

        def chosen(w):
            mid = w.get_active_id()
            if mid is not None:
                w.get_child().set_text(mid)  # the id, not the label with its note
                if mid != getattr(self.app.ling.config(), kind + "_model"):
                    self.app.set_ai_model(kind, mid)
        c.connect("changed", chosen)
        c.get_child().connect("activate", lambda e: self.app.set_ai_model(kind, e.get_text().strip()))
        if getattr(self, "scroll", None) is not None:
            ui.no_wheel(c, self.scroll)
        return c

    def _uses_rows(self) -> list:
        """现在能用的 (AISettings.swift › usage), with 听对方 first: on the ports the service hears. Only
        what the last result supports: when the service can't be reached or the key fails, nothing
        says "用 ZenMux" in green."""
        from ..core import aicheck
        ling = self.app.ling
        c = ling.config()
        r = ling.check_result
        name = L(c.provider.name) if c.provider.id == "custom" else c.provider.name
        reason = r.reason
        down = ling.has_key and r.down
        on = ling.usable and not down
        text_on = on and reason != aicheck.NO_MODEL
        notes_on = text_on and reason != aicheck.NO_JSON
        hear_on = on and ling.hears is not False
        uses = LF("用 %@", name)
        later = ((LF("连上 %@ 后可用", name) if reason == aicheck.UNREACHABLE else L("换好 key 后可用")) if down
                 else L("填好 key 后可用"))
        off = L("暂不可用") if ling.has_key else L("需要 key")
        rows = []
        if hear_on:
            hear = (uses, "ok", L("Ming 一次识别并翻译") if c.is_ling else c.hear_model + " · " + L("比 Ling 晚 1–2 秒出字"))
        elif on:
            hear = (off, "off", LF("%@ 听不了声音。", c.hear_model) if c.hear_model else L("换一个模型后可用"))
        else:
            hear = (off, "off", later)
        rows.append((L("听对方"),) + hear)
        if notes_on and r.busy:
            rows.append((L("实时纪要"), L("很忙"), "warn", L("会自动重试，纪要可能晚一点")))
        else:
            rows.append((L("实时纪要"),) + ((uses, "ok", L("会中每 45 秒更新")) if notes_on else
                                          (off, "off", L("这个服务不支持 JSON") if reason == aicheck.NO_JSON
                                           else L("换一个模型后可用") if reason == aicheck.NO_MODEL else later)))
        rows.append((L("翻译"),) + ((uses, "ok", L("整句用它；不行时换 Google")) if text_on else
                                  ("Google", "off", L("先用 Google 翻译") if ling.has_key else L("没有 key 时照常可用"))))
        # 改正听错的词: on Linux one more text request per sentence (Ming already translated it).
        fix_on = text_on and self.app.settings.fixMisheard
        rows.append((L("改正听错的词"), uses if fix_on else L("已关") if text_on else off, "ok" if fix_on else "off",
                     L("每句多发一次文字请求") if fix_on else L("在“词表”里打开") if text_on else later))
        if ling.speaks and hear_on:
            # 同传 hears me with the hear model first, then speaks with the voice model.
            if ling.last_voice is not None:
                note = L("上次同传时正常") if ling.last_voice[0] else L("上次同传没出声")
            else:
                note = L("Ming 的声音") if c.is_ling else c.voice_model
            rows.append((L("同传声音"), uses, "ok", note))
        elif ling.speaks:
            rows.append((L("同传声音"), off, "off", LF("%@ 听不了声音。", c.hear_model) if on else later))
        else:
            rows.append((L("同传声音"), L("用不了") if on else off, "off", L("这个服务不能出声音") if on else later))
        if not c.is_ling:
            rows.append((L("你自己的声音"), L("只有 Ling"), "ling", L("换用 Ling 才有")))
        out = []
        for title, tag, style, note in rows:
            label = ui.text(tag, 11, "", bold=True, wrap=False, ellipsize=False)
            chip = ui.panel(ui.pad(label, 2, 8), "aitag", style)
            out.append(ui.prow(title, chip, note))
        return out

    def _model_rows(self) -> list:
        app = self.app
        c = app.ling.config()
        p = c.provider
        if p.id == "ling":
            menu = choice([(m.id, m.id) for m in p.text_models], c.text_model, lambda v: app.set_ai_model("text", v))
            if getattr(self, "scroll", None) is not None:
                ui.no_wheel(menu, self.scroll)
            return [ui.prow(L("文字模型"), menu, L("3.1 更准；3.0 更快、更省")),
                    ui.prow(L("听的模型"), ui.text(c.hear_model, 12, "tertiary", wrap=False), L("Ming 一次识别并翻译"))]
        if p.id == "custom":
            return []  # its models are in its own rows (_custom_page)
        rows = [ui.prow(L("听的模型"), self._model_menu("hear", c.hear_model, p.hear_models, app.ling.hear_catalog),
                        L("听对方和“我说”都用它")),
                ui.prow(L("文字模型"), self._model_menu("text", c.text_model, p.text_models, app.ling.text_catalog), L("纪要和整句翻译"))]
        if p.has_voices:
            rows.append(ui.prow(L("声音模型"), self._model_menu("voice", c.voice_model, p.voice_models, []), L("同传念给对方")))
        return rows

    def show_key_state(self) -> bool:
        app = self.app
        c = app.ling.config()
        p = c.provider
        k = app.ling.current_key()
        state = app.ling.key_state
        name = L(p.name) if p.id == "custom" else p.name
        ui.clear(self.key_status)
        have = k is not None
        ui.retext(self.key_line, AIKey.masked(k) if k else (L("本机服务，不用 key") if have else
                                                           (L("还没填好") if p.id == "custom" else L("还没填 API key"))))
        from ..core import aicheck
        from . import aicheck_view
        r = app.ling.check_result
        f = r.failure
        if r.running or state == lingmod.CHECKING:
            icon_name, cls, label = "content-loading-symbolic", "secondary", L("正在检查…")
        elif f is not None and f[1] != aicheck.BUSY:
            # Named after the step that failed: a missing model is not a connection problem.
            label = {"reach": L("暂时连不上"), "key": L("这个 key 用不了")}.get(f[0], L("模型用不了"))
            icon_name, cls = "dialog-warning-symbolic", "warn"
        elif r.busy:
            icon_name, cls, label = "dialog-warning-symbolic", "busyline", LF("%@ 现在很忙", name)
        elif state == lingmod.OK:
            line = aicheck_view.passed_line(app)
            icon_name, cls, label = "object-select-symbolic", "ok", L("已连接") + (" · " + line if line else "")
        else:
            icon_name, cls, label = None, "secondary", ""
        if have and label:
            if icon_name:
                img = ui.icon(icon_name, 14)
                ui.classes(img, cls)
                self.key_status.pack_start(img, False, False, 0)
            self.key_status.pack_start(ui.text(label, 12, cls, width_chars=48), False, False, 0)
        self.key_status.show_all()
        self.key_status.set_visible(have and bool(label))
        self.change_button.set_visible(bool(k))
        self.recheck_button.set_visible(have)
        self.recheck_button.set_sensitive(not r.running)
        self.remove_button.set_visible(bool(k))
        self.entry_row.set_visible(not k or state == lingmod.INVALID or (self.entry_row.get_visible() and bool(self.key_hint.get_children())))
        # The steps, rebuilt when they change.
        steps_key = (r.summary(), r.at is None, c.text_model, c.hear_model, have)
        if steps_key != getattr(self, "_steps_shown", None):
            self._steps_shown = steps_key
            ui.clear(self.steps)
            if have and aicheck_view.show_steps(r):
                self.steps.pack_start(aicheck_view.steps_widget(app, self._change_key, recheck_in_step=False), False, False, 0)
                self.steps.show_all()
                self.steps_card.get_child().show_all()  # show_all stops at a no_show_all widget
                self.steps_card.set_visible(True)
            else:
                self.steps_card.set_visible(False)
            ui.clear(self.balance_row)
            low = r.balance_line(name) if have else None
            if low:
                self.balance_row.pack_start(ui.text(low, 12, "", width_chars=40), True, True, 0)
                b = ui.button(L("去充值"), lambda: open_uri(aicheck_view.top_up_url(p)), "outline")
                b.set_valign(Gtk.Align.CENTER)
                self.balance_row.pack_end(b, False, False, 0)
                self.balance_strip.get_child().show_all()
            self.balance_strip.set_visible(bool(low))
        custom = p.id == "custom"
        self.custom_page.set_visible(custom)
        self.key_group.set_visible(not custom)
        self.uses_group.set_visible(not custom)
        self.fold.set_visible(not custom)
        if custom:
            self.steps_card.set_visible(False)  # under 翻译和纪要 instead
            self.models.set_visible(False)
            self._show_custom()
        self.get_key.set_visible(p.site is not None and not k)
        ui.retext(self.get_key_label, L("获取 Ling key") if p.id == "ling" else LF("打开 %@", name))
        host = (c.base or "").split("//")[-1].split("/")[0] or L("你填的地址")
        if custom:
            # Where the key goes: every use's address, the notes' only while they share it.
            from ..core.providers import hosts
            host = _hosts_words(hosts(c, notes=not app.ling.notes_has_own_key))
        ui.retext(self.lock_line, L("仅保存在本机当前账户下，仅发送至 Ling（ant-ling.com）") if p.id == "ling"
                  else LF("仅保存在本机当前账户下，仅发送至 %@", host) if p.id == "custom" else LF("仅保存在本机当前账户下，仅发送至 %@（%@）", name, host))
        if custom:
            # The user's own machines aren't billed by use; the audio still leaves this computer
            # for the hear model's address (never 声音不出本机 on a port).
            from ..core.providers import is_nearby
            cost = L("跑在你自己的机器上，不按量计费。") if c.base and is_nearby(c.base) else L("费用以这个服务为准。")
            if app.settings.aiCustomOnly:
                from ..core.providers import hosts
                ui.retext(self.footnote, cost + LF("会议的语音和文字只发给 %@，不经过 Google 等外部服务。", _hosts_words(hosts(c))))
            else:
                ui.retext(self.footnote, cost + LF("听的时候，电脑里的声音会发给 %@。", app.ling.hear_host or L("你填的地址")))
        else:
            ui.retext(self.footnote, LF("听的时候，电脑里的声音会发给 %@。", name) if p.id == "ling"
                      else L("按所选模型计费。") + LF("听的时候，电脑里的声音会发给 %@。", name))
        # The rows that depend on the service and what its check found.
        shown = (p.id, state, app.ling.hears, bool(k), c.text_model, c.hear_model, c.voice_model,
                 len(app.ling.text_catalog), len(app.ling.hear_catalog), r.reason, r.busy, app.ling.last_voice)
        if shown != getattr(self, "ai_shown", None):
            self.ai_shown = shown
            ui.clear(self.uses)
            self.uses.pack_start(ui.boxed(self._uses_rows()), False, False, 0)
            self.uses.show_all()
            ui.clear(self.models)
            self.models.pack_start(ui.boxed(self._model_rows()), False, False, 0)
            if self.models.get_visible():
                self.models.foreach(lambda w: w.show_all())
            if self.provider_menu.get_active_id() != p.id:
                self.provider_menu.set_active_id(p.id)
            if hasattr(self, "_fill_voices"):
                self._fill_voices()
            if hasattr(self, "voice_box"):
                self.voice_box.set_sensitive(app.ling.speaks or not app.ling.usable)
        return False

    def save_key(self) -> None:
        app, s = self.app, self.app.settings
        if s.aiProvider == "custom":
            # The address and models typed so far, kept even before a key.
            s.aiCustomBase = self.custom_base.get_text().strip()
            s.aiModels["custom"] = self.custom_text.text()
            notes_model = self.notes_model.text()
            if notes_model:
                s.aiModels["custom.notes"] = notes_model
            else:
                s.aiModels.pop("custom.notes", None)
            if s.aiCustomNotesOwn:  # 同一个服务 keeps the address typed before
                s.aiCustomNotesBase = self.notes_base.get_text().strip()
            s.aiHearModels["custom"] = self.custom_hear.get_text().strip()
            s.aiCustomHearBase = self.custom_hear_base.get_text().strip()
            s.aiVoiceModels["custom"] = self.custom_voice_model.get_text().strip()
            s.aiCustomVoice = self.custom_voice.get_text().strip()
            s.aiCustomVoiceBase = self.custom_voice_base.get_text().strip()
            s.save()
        entry = self.custom_key if s.aiProvider == "custom" else self.key_entry
        text = entry.get_text().strip()
        self._show_key_hint(None)
        if text:
            # The prefix says whose key it is: a management key can't call models, and another
            # service's key goes there with one click (never a silent switch).
            from . import aicheck_view
            hint = aicheck_view.key_hint(app, text)
            if hint is not None:
                self._show_key_hint(hint, text)
                return
            if not app.key.save(text):
                return
            entry.set_text("")
        self.custom_editing = False
        # Notes' own key (另一个服务): saved here too; it goes only to the notes' address.
        nk = self.notes_key.get_text().strip()
        if s.aiProvider == "custom" and nk and s.aiCustomNotesOwn and app.ling.notes_key_file.save(nk):
            self.notes_key.set_text("")
            self.notes_editing = False
        app.ai_changed()

    def _show_key_hint(self, hint, key: str = "") -> None:
        for box in (self.key_hint, self.custom_key_hint):
            ui.clear(box)
            box.set_visible(False)
        if hint is None:
            return
        box = self.custom_key_hint if self.app.settings.aiProvider == "custom" else self.key_hint
        box.set_visible(True)
        words, service = hint
        box.pack_start(ui.text(words, 12, "stepwhy", width_chars=40), True, True, 0)
        if service:
            from ..core.providers import named

            def switch():
                self._show_key_hint(None)
                self.key_entry.set_text("")
                self.custom_key.set_text("")
                self.app.switch_service(service, key)
            b = ui.button(LF("改用 %@", named(service).name), switch, "darkbtn")
            b.set_valign(Gtk.Align.CENTER)
            box.pack_end(b, False, False, 0)
        for w in box.get_children():
            w.show_all()

    def _change_key(self) -> None:
        """更换 key from a failed step: the field opens, focused."""
        self.entry_row.set_visible(True)
        self.key_entry.grab_focus()

    def remove_key(self) -> None:
        self.app.key.remove()
        self.app.ai_changed()

    @staticmethod
    def _open_folder(path) -> None:
        os.makedirs(path, exist_ok=True)
        open_uri("file://" + path)


def _hosts_words(hosts: list) -> str:
    """One host, "a 和 b", or 你填的地址 for more (AISettings.swift › customHosts)."""
    if len(hosts) == 1:
        return hosts[0]
    if len(hosts) == 2:
        return LF("%@ 和 %@", hosts[0], hosts[1])
    return L("你填的地址")


class ModelPicker:
    """A custom service's model (AISettings.swift › ModelPicker): the names its `/models` lists, in
    the menu and searched as you type, and any name typed that it doesn't list (an alias, a model it
    hides): 用 X（列表里没有）. Enter takes the only match, else what was typed. `same_label`: a first
    choice that clears the value (和翻译模型一样). Without a list it is a plain field. Picking calls
    `on_pick`; 重新获取 calls `refetch`."""

    def __init__(self, label: Gtk.Widget, value: str, placeholder: str, on_pick, refetch, same_label: str | None = None):
        self.on_pick = on_pick
        self.same_label = same_label
        self.catalog: tuple = ()
        self._filling = False
        self.combo = Gtk.ComboBoxText.new_with_entry()
        self.entry = self.combo.get_child()
        self._action = False
        self.entry.connect("changed", lambda *_: self._typed())
        self.entry.set_text(value)
        self.entry.set_placeholder_text(same_label or placeholder)
        self.entry.set_width_chars(26)
        self.entry.connect("activate", lambda *_: self._enter())
        self.combo.connect("changed", self._chosen)
        self.combo.set_button_sensitivity(Gtk.SensitivityType.OFF)
        # Search: every listed name that contains what's typed, any case.
        self.store = Gtk.ListStore(str)
        self.completion = Gtk.EntryCompletion()
        self.completion.set_model(self.store)
        self.completion.set_text_column(0)
        self.completion.set_minimum_key_length(1)
        self.completion.set_match_func(lambda _c, key, it: key.strip().lower() in (self.store[it][0] or "").lower())
        self.completion.connect("match-selected", lambda _c, model, it: (self.pick(model[it][0]), True)[1])
        self.completion.connect("action-activated", lambda *_: self.pick(self.text()))
        self.entry.set_completion(self.completion)
        self.refetch_button = ui.button(L("重新获取"), refetch, "outline")
        self.refetch_button.set_valign(Gtk.Align.CENTER)
        self.refetch_button.set_no_show_all(True)
        self.footer = ui.text("", 11, "tertiary", wrap=False)
        self.footer.set_no_show_all(True)
        row = ui.hbox(8, label)
        row.pack_start(self.combo, True, True, 0)
        row.pack_end(self.refetch_button, False, False, 0)
        # The list's line sits under the field, past the row's label (34 px and the 8 px gap).
        self.widget = ui.vbox(4, row, ui.pad(self.footer, 0, 0, 0, 42))

    def text(self) -> str:
        return self.entry.get_text().strip()

    def fill(self, catalog, host: str) -> None:
        """The names `host` lists (empty: none, or not fetched yet). Keeps what's typed."""
        listed = tuple(catalog)
        self.refetch_button.set_visible(bool(host))
        if listed == self.catalog:
            return
        self.catalog = listed
        typed = self.entry.get_text()
        self._filling = True
        self.combo.remove_all()
        if listed and self.same_label:
            self.combo.append("", self.same_label)
        for mid in listed:
            self.combo.append(mid, mid)
        self.store.clear()
        for mid in listed:
            self.store.append([mid])
        self.entry.set_text(typed)
        self._filling = False
        self.combo.set_button_sensitivity(Gtk.SensitivityType.ON if listed else Gtk.SensitivityType.OFF)
        self.entry.set_tooltip_text(None if listed else L("这个地址没列出模型，直接填名字"))
        ui.retext(self.footer, LF("%@ 列出 %lld 个模型", host, len(listed)) if listed else "")
        self.footer.set_visible(bool(listed))

    def pick(self, mid: str) -> None:
        self._filling = True
        self.entry.set_text(mid)
        self._filling = False
        self.on_pick(mid)

    def _chosen(self, combo) -> None:
        mid = combo.get_active_id()
        if mid is not None and not self._filling:
            self.pick(mid)  # the id: 和翻译模型一样 is ""

    def _enter(self) -> None:
        q = self.text()
        matches = [m for m in self.catalog if q.lower() in m.lower()] if q else list(self.catalog)
        self.pick(matches[0] if len(matches) == 1 else q)

    def _typed(self) -> None:
        """用 X（列表里没有）, under the matches, while what's typed isn't a listed name."""
        if self._action:
            self.completion.delete_action(0)
            self._action = False
        q = self.text()
        # Names in mono, as on the Mac; the placeholder (和翻译模型一样) in the UI font.
        (self.entry.get_style_context().add_class if q else self.entry.get_style_context().remove_class)("mono")
        if q and self.catalog and q not in self.catalog:
            self.completion.insert_action_text(0, LF("用 %@（列表里没有）", q))
            self._action = True


def _labels(w) -> list:
    out = [w] if isinstance(w, Gtk.Label) else []
    if hasattr(w, "get_children"):
        for c in w.get_children():
            out += _labels(c)
    return out
