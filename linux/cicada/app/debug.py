"""The dev build's control socket ($XDG_RUNTIME_DIR/cicada-dev.sock, this user only), the Linux
counterpart of tools/lsctl and the Windows named pipe; scripts/cicadactl talks to it. One command
per connection, one JSON line back. Never in release builds.

  state | start | stop | feed <wav> | sample | view notes|subtitles | show records|notes|settings|onboarding
  target <code> | key-reload | windows | select <record id> | append <record id> <n> (a growing meeting)
  provider ling|openrouter|zenmux|custom | ai-model hear|text|voice|notes <id> (设置 › AI 服务; "" back to the recommended) |
  ai-base text|voice|hear|notes <url> (其他（兼容 OpenAI）'s addresses; "" for voice/hear/notes: the text one)
  ai-notes same|own (纪要: 同一个服务 / 另一个服务, the Mac's aiCustomNotesOwn)
  ai-custom-only on|off (语音和文字只发给你的服务, the Mac's aiCustomOnly)
  speak-enable on|off | speak on|off (同声传译) | quit
  calls <program=name,…>|none|real (meeting apps in a call) | endtimes <silence> <countdown> <grace>|off | endkeep
  notes-tab notes|transcript | notes-search <text> | notes-wide on|off | onboarding-step <n> | settings-scroll <0-1>
  settings-models on|off (unfold 自己选模型)
  ai-check-sim <reason|lowBalance|off> (every check ends this way: screenshots of each state) | ai-check (check now)
  ask settings|fix|close (answer the 开始听 dialog a failed check put up) | settings-ai (设置 at AI 服务) | tray-menu
  pill (the records window capsule's widget sizes)
  listen-source system|room|both (听哪里) | room-mic [<source>|auto] | lines [<record id>] (each line's via)
  online both|no (answer 线上也有人？) | room-mic-force <source>|"" (a null sink's monitor as the room mic)
  hide notes | problem-wait <seconds>|off (how long unreachable lasts before its notification; off: 2 min)
  codecs (AAC encoder / decoders here) | play [<seconds>] | pause | rate (next speed) | playstate (the shown record's
  recording: state, time, length, rate, the highlighted line, following, the 回到正在播放 capsule, the scroll) |
  follow (press 回到正在播放) | play-line <index> (click a line) | line-rect <index>|pill (on the screen) |
  settings-general (设置 at 通用)
  share <record id>[,full][,pw] | unshare <record id> | share-last (how the last ended) | shareSheet <record id>|""
  share-ui scope notes|full | days 7|30|365 | names|pw|summary on|off | options (更改) | go | strip | back | confirm
           | copy all|link|password | revoke | close | state
  export-folder <path>|off|on (存到文件夹: choose a folder as 存到这里 does, and its check) |
  export-state (folder, problem, index, the records not written yet) | export-all (也存一份) | export-retry |
  export-choose (open 存到哪里, as 更改… does; answer it with the dialog itself)
  voice <lang> | voice <lang>=<id> (the voice a language uses: "voice en=clone", "voice zh=灵小锋")
  voice-clone <wav>|off|state (我自己的声音 from a 16 kHz WAV: Ming hears it, the Mac's checks, then kept; state
           says the last result and the files' modes) | voice-preview [<lang>] (试听 in that language: what played)
  voice-dialog open|feed <wav>|finish|play original|clone|save|close|state (the record sheet, a WAV as the mic)"""
from __future__ import annotations

import os
import socket
import threading
import time

from gi.repository import GLib

from ..core import jsonfmt
from ..core.support import Log, Paths


def path() -> str:
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "cicada-dev.sock")


def start(app) -> None:
    p = path()
    try:
        os.unlink(p)
    except OSError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    old = os.umask(0o077)
    try:
        server.bind(p)
    finally:
        os.umask(old)
    server.listen(4)
    threading.Thread(target=_serve, args=(app, server), name="Debug", daemon=True).start()
    Log.d("debug: listening on %s" % p)


def _serve(app, server) -> None:
    while True:
        conn, _ = server.accept()
        with conn:
            try:
                data = b""
                while not data.endswith(b"\n"):
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                reply = _on_main(app, data.decode().strip())
            except Exception as e:  # noqa: BLE001 - report, don't kill the server
                reply = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
            conn.sendall((jsonfmt.write(reply, pretty=False) + "\n").encode())


def _on_main(app, line: str) -> dict:
    done = threading.Event()
    box = {}

    def run():
        try:
            box["r"] = command(app, line)
        except Exception as e:  # noqa: BLE001
            box["r"] = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
        done.set()
        return False
    GLib.idle_add(run)
    done.wait(10)
    return box.get("r", {"ok": False, "error": "timeout"})


def _window(w) -> dict | None:
    if w is None:
        return None
    x, y = w.get_position()
    width, height = w.get_size()
    gdk = w.get_window()
    return {"visible": w.get_visible(), "x": x, "y": y, "w": width, "h": height, "title": w.get_title(),
            "xid": gdk.get_xid() if gdk is not None and hasattr(gdk, "get_xid") else None,
            "acceptFocus": w.get_accept_focus(), "active": w.is_active(),
            "iconified": getattr(w, "iconified", None)}


def _speakers(app, s) -> dict:
    from ..core import speakers
    out = {"on": app.settings.speakerVoices, "available": app.voices_available, "model": app.speakers._model is not None}
    if s is not None:
        vnums = speakers.voice_numbers(s.lines)
        out.update({"voices": sorted({l.voice for l in s.lines if l.voice is not None}),
                    "shown": {str(v): n for v, n in vnums.items()}, "names": {str(k): v for k, v in speakers.names(s).items()},
                    "tagged": sum(1 for l in s.lines if l.voice is not None), "lines": len(s.lines),
                    "byVoice": [[l.id, l.voice, l.src[:40]] for l in s.lines]})
    return out


def _problem(app) -> dict:
    from .aicheck_view import blocking
    w = app.notes_window
    return {"blocking": blocking(app), "reason": app.ling.check_result.reason, "sent": sorted(app.notices.sent),
            "wait": app.notices.wait, "notesShown": bool(w is not None and w.get_visible()),
            "tray": app.tray.badged[1] if app.tray is not None else None}


def updates_notified():
    from ..core import updates
    return updates.notified()


def _export(app, cmd: str, arg: str) -> dict:
    """存到文件夹. Waits for the exporter's worker (it never waits for the main loop), so the reply
    says what happened."""
    ex = app.folder_export
    if cmd == "export-folder":
        if arg == "off":
            ex.turn_off()
        elif arg == "on" and ex.folder:
            ex.choose(ex.folder)
        elif arg:
            ex.choose(arg)
        else:
            return {"ok": False, "error": "export-folder <path>|off|on"}
        ex.wait()
        return {"ok": True, **ex.state()}
    if cmd == "export-all":
        ex.write_all()
        ex.wait()
        return {"ok": True, **ex.state()}
    if cmd == "export-retry":
        ex.retry()
        return {"ok": True}
    if cmd == "export-choose":
        app.show_settings(general=True)
        GLib.idle_add(lambda: app.settings_window.folder_card._choose() and False)
        return {"ok": True}
    if cmd == "export-state":
        return {"ok": True, **ex.state()}
    return {"ok": False, "error": "unknown command"}


def command(app, line: str) -> dict:
    parts = line.split(" ", 1)
    cmd, arg = parts[0], (parts[1] if len(parts) > 1 else "")
    listen = app.listen
    if cmd == "state":
        sid = listen.session_id
        s = app.store.get(sid) if sid else None
        last = s.lines[-1] if s and s.lines else None
        n = app.notes.notes
        return {"ok": True, "listening": listen.listening, "session": sid, "source": listen.source_kind,
                "lines": len(s.lines) if s else 0, "last": {"src": last.src, "dst": last.dst, "lang": last.srcLang} if last else None,
                "pending": listen.pending, "problem": listen.problem, "problemKind": listen.problem_kind, "heardSeconds": round(listen.heard_seconds, 1),
                "peak": round(listen.peak, 4), "notes": {"title": n.title, "topics": len(n.topics), "status": app.notes.status, "final": n.final},
                "key": app.ling.key_state, "ai": _ai(app), "view": app.settings.view, "listenSource": app.settings.listenSource,
                "mic": app.mic_on,
                "hybrid": {"roomSide": listen.hears_room_too, "echoCancel": app.echo.on, "gated": listen.gated,
                           "echo": listen.echo_gate.echo, "music": listen.echo_gate.playing_music(time.monotonic())},
                "target": app.settings.target_code,
                "ui": __import__("cicada.core.strings", fromlist=["language"]).language, "records": len(app.store.all()),
                "tray": app.tray is not None, "home": Paths.data(),
                "speak": {"enabled": app.settings.speakEnabled, "room": app.room.on, "active": app.speak.active, "stage": app.speak.stage,
                          "spoken": app.speak.spoken, "problem": app.speak.problem, "to": app.speak.target,
                          "last": list(app.speak.last) if app.speak.last else None},
                "speakers": _speakers(app, s),
                "ending": {"title": app.ending_title(app.ending), "left": app.ending_left(app.ending),
                           "reason": repr(app.ending.reason)} if app.ending else None,
                "aiProblem": _problem(app),
                "autoEnded": app.auto_ended, "fakeCalls": app.fake_calls,
                "endTimes": list(app.end_times) if app.end_times else None,
                "inCall": dict(app.end_watch.in_call) if app.end_watch else None}
    if cmd == "start":
        # Later, not here: 开始听 may ask first (a deaf hear model), and its dialog runs its own loop.
        if not listen.listening:
            GLib.idle_add(lambda: app.toggle_listening() and False)
        return {"ok": True}
    if cmd == "ai-check-sim":
        from ..core import aicheck
        if arg not in aicheck.REASONS + ("lowBalance", "off"):
            return {"ok": False, "error": "reason, lowBalance or off"}
        app.ling.simulate = None if arg == "off" else arg
        threading.Thread(target=app.ling.check, daemon=True).start()
        return {"ok": True, "simulate": app.ling.simulate}
    if cmd == "hide" and arg == "notes":
        if app.notes_window is not None:
            app.notes_window.hide()
        return {"ok": True}
    if cmd == "problem-wait":
        from ..core.problem import UNREACHABLE_AFTER
        app.notices.wait = UNREACHABLE_AFTER if arg == "off" else float(arg)
        return {"ok": True, "problem": _problem(app)}
    if cmd == "ai-check":
        threading.Thread(target=app.ling.check, daemon=True).start()
        return {"ok": True}
    if cmd == "ask":
        from gi.repository import Gtk
        d = getattr(app, "_asking", None)
        if d is None:
            return {"ok": False, "error": "no question open"}
        d.response({"settings": Gtk.ResponseType.CANCEL, "fix": Gtk.ResponseType.ACCEPT}.get(arg, Gtk.ResponseType.CLOSE))
        return {"ok": True}
    if cmd == "tray-menu":
        # The top-bar menu's items (opening it takes a real click on the top bar).
        if app.tray is None:
            return {"ok": False, "error": "no tray"}
        return {"ok": True, "items": [i.get_label() for i in app.tray.menu.get_children() if hasattr(i, "get_label")]}
    if cmd == "settings-ai":
        app.show_settings(ai=True)
        return {"ok": True}
    if cmd in ("mic", "listen-source"):  # 打开麦克风 (on|off); listen-source both|room|system, the old names
        app.set_mic(arg in ("on", "both", "room"))
        return {"ok": True, "mic": app.mic_on, "source": listen.source_kind}
    if cmd == "room-echo-sim":  # pretend the speakers do (on) or don't (off) reach the room mic; real
        listen.echo_gate.forced = None if arg in ("", "real") else arg != "off"
        return {"ok": True, "echo": listen.echo_gate.echo}
    if cmd == "room-echo":  # the sound server's echo cancellation for the room mic (on|off), next start
        app.room_echo_cancel = arg == "on"
        return {"ok": True}
    if cmd == "room-mic-force":  # any source as the room mic, e.g. a null sink's monitor ("" = off)
        app.forced_room_mic = arg or None
        return {"ok": True, "forced": app.forced_room_mic}
    if cmd == "room-mic":  # which microphone 会议室 would use now; with an argument, choose it ("" = 自动)
        if arg:
            app.settings.roomMic = "" if arg == "auto" else arg
            app.settings.save()
        return {"ok": True, "roomMic": app.settings.roomMic, "picked": app.room_mic()}
    if cmd == "lines":  # the live (or given) meeting's lines: where each was heard
        s = app.store.get(arg or listen.session_id or "")
        return {"ok": True, "room": s.room if s else None,
                "lines": [[l.id, l.speaker, l.via, l.src[:50]] for l in s.lines] if s else []}
    if cmd == "stop":
        app.stop_listening()
        return {"ok": True}
    if cmd == "updatecheck":  # the Mac's updateCheck: check the feed now (CICADA_UPDATE_FEED in a dev build)
        app.updates.check_now()
        return {"ok": True}
    if cmd == "updateinstall":  # the Mac's updateInstall: what 安装并重新打开 does
        app.updates.install()
        return {"ok": True}
    if cmd == "updatestate":
        u = app.updates
        return {"update": u.update.version if u.update else None, "notified": updates_notified(),
                "afterMeeting": u.after_meeting, "failure": u.failure, "opened": u.opened,
                "progress": u.progress, "detail": u.detail()}
    if cmd == "feed":
        if not os.path.isfile(arg):
            return {"ok": False, "error": "no such file"}
        app.feed(arg)
        return {"ok": True}
    if cmd == "sample":
        app.play_sample()
        return {"ok": True}
    if cmd == "view":
        app.set_view(arg)
        return {"ok": True, "view": app.settings.view}
    if cmd == "dock":  # dock on|off: 在 Dock 中显示, as its switch sets it
        if arg in ("on", "off"):
            app.set_show_in_dock(arg == "on")
        w = app.records_window
        return {"ok": True, "on": app.settings.showInDock, "records": _window(w),
                "parked": w.parked if w is not None else None}
    if cmd == "close" and arg == "records":  # the ✕ of the records window
        if app.records_window is not None:
            app.records_window.close()
        return {"ok": True}
    if cmd == "show":
        {"records": app.show_records, "notes": app.show_notes, "settings": app.show_settings,
         "onboarding": app.show_onboarding}[arg]()
        return {"ok": True}
    if cmd == "target":
        app.settings.target = arg
        app.settings.save()
        return {"ok": True, "target": app.settings.target_code}
    if cmd == "key-reload":
        app.key.reload()
        app.ling.key_changed()
        threading.Thread(target=app.ling.check, daemon=True).start()
        return {"ok": True}
    if cmd == "provider":
        app.set_ai_provider(arg)
        return {"ok": True, "ai": _ai(app)}
    if cmd == "switch-to-ling":  # the 改用 Ling on a status line (says whether it was offered)
        offered = app.can_switch_to_ling()
        Log.d("switchToLing offered=%s" % offered)
        app.switch_to_ling()
        return {"ok": True, "offered": offered, "ai": _ai(app)}
    if cmd == "ai-base":
        # A custom service's addresses: text, voice or hear ("" for voice and hear: the text one).
        kind, _, url = arg.partition(" ")
        field = {"text": "aiCustomBase", "voice": "aiCustomVoiceBase", "hear": "aiCustomHearBase",
                 "notes": "aiCustomNotesBase"}.get(kind)
        if field is None:
            return {"ok": False, "error": "ai-base text|voice|hear|notes <url>"}
        setattr(app.settings, field, url.strip())
        app.settings.save()
        app.ai_changed()
        return {"ok": True, "ai": _ai(app)}
    if cmd == "ai-notes":
        app.settings.aiCustomNotesOwn = arg == "own"
        app.settings.save()
        app.ai_changed()
        return {"ok": True, "ai": _ai(app)}
    if cmd == "ai-custom-only":
        app.set_custom_only(arg == "on")
        return {"ok": True, "ai": _ai(app)}
    if cmd == "ai-model":
        kind, _, model = arg.partition(" ")
        app.set_ai_model(kind, model.strip())
        return {"ok": True, "ai": _ai(app)}
    if cmd == "windows":
        return {"ok": True, "notes": _window(app.notes_window), "records": _window(app.records_window),
                "settings": _window(app.settings_window), "onboarding": _window(app.onboarding)}
    if cmd == "pill":
        # The records window's capsule as a tree of allocations (checking it against the Mac's sizes).
        def tree(w, depth=0):
            a = w.get_allocation()
            ctx = w.get_style_context()
            out = ["%s%s %dx%d+%d+%d %s" % ("  " * depth, type(w).__name__, a.width, a.height, a.x, a.y,
                                            ".".join(ctx.list_classes()))]
            if hasattr(w, "get_children") and depth < 8:
                for c in w.get_children():
                    out += tree(c, depth + 1)
            return out
        return {"ok": True, "tree": tree(app.records_window.listen_box)} if app.records_window else {"ok": False}
    if cmd == "speakers":
        # speakers on|off; speakers <session id>: the voices of a record
        if arg in ("on", "off"):
            app.set_speaker_voices(arg == "on")
            return {"ok": True, "on": app.settings.speakerVoices}
        return {"ok": True, **_speakers(app, app.store.get(arg))}
    if cmd == "speak-enable":
        return {"ok": app.set_speak_enabled(arg == "on"), "enabled": app.settings.speakEnabled, "realMic": app.room.real_mic,
                "talkEcho": app.talk_echo.on}
    if cmd == "speak":
        if (arg == "on") != app.speak.active:
            app.toggle_speaking()
        # echoCancelled: this press reads the talk key's echo canceller (else the plain mic, echo drop on)
        return {"ok": True, "speaking": app.speak.active, "echoCancelled": app.speak.echo_cancelled}
    if cmd.startswith("voice"):
        return _voice(app, cmd, arg)
    if cmd == "codecs":
        from . import media
        return {"ok": True, **media.codecs(), "recordAudio": app.settings.recordAudio, "recording": listen.recording}
    if cmd == "line-rect":  # where transcript row <n> (or the 回到正在播放 capsule: "pill") is on the screen, for real clicks
        w = app.records_window
        widget = w.back_pill if arg == "pill" else w._rows[int(arg)][1] if w is not None and int(arg) < len(w._rows) else None
        if widget is None or not widget.get_mapped():
            return {"ok": False, "error": "not shown"}
        x, y = widget.translate_coordinates(w, 0, 0)
        ox, oy = w.get_window().get_origin()[1:]
        a = widget.get_allocation()
        return {"ok": True, "x": ox + x, "y": oy + y, "w": a.width, "h": a.height}
    if cmd in ("play", "pause", "rate", "playstate", "follow", "play-line"):
        w = app.records_window
        p = w.player if w is not None else None
        if cmd != "playstate" and p is None:
            return {"ok": False, "error": "no recording shown"}
        if cmd == "play":
            p.play_from(float(arg)) if arg else p.play()
        elif cmd == "pause":
            p.pause()
        elif cmd == "rate":
            p.next_rate()
        elif cmd == "follow":
            w.follow_playing()
        elif cmd == "play-line":
            s = app.store.get(w._player_sid)
            w.play_line(s.lines[int(arg)])
        hl = w._hl_row if w is not None else None
        sid = w.selected if w is not None else None
        s = app.store.get(sid) if sid else None
        return {"ok": True, "record": sid, "audio": w._built_key[3] if w is not None and w._built_key else None,
                "hasAudio": s.hasAudio if s else None, "playing": p.playing if p else None,
                "time": round(p.time, 2) if p else None, "length": round(p.length, 2) if p else None,
                "rate": p.rate if p else None, "following": p.following if p else None,
                "pill": w._pill_label.get_text() if w is not None and w.back_pill.get_visible() else None,
                "scroll": round(w.right.get_vadjustment().get_value()) if w is not None else None,
                "bars": w._bars is not None and w._bars.get_mapped() if w is not None else None,
                "bar": w.bottom.get_children() != [] if w is not None else None,
                "line": next((i for i, (_k, r) in enumerate(w._rows) if r is hl), None) if hl is not None else None}
    if cmd.startswith("export-"):
        return _export(app, cmd, arg)
    if cmd == "settings-general":
        app.show_settings(general=True)
        return {"ok": True}
    if cmd == "select":
        app.show_records()
        app.records_window.selected = arg
        app.records_window.fill()
        return {"ok": True}
    if cmd == "append":
        # A meeting growing line by line, as while listening: `append <id> <n>`.
        from ..core.models import TranscriptLine
        sid, n = arg.split()
        s = app.store.get(sid)
        if s is None:
            return {"ok": False, "error": "no such record"}
        base = len(s.lines)

        def add(i=[0]):
            k = base + i[0]
            app.store.append(sid, TranscriptLine(id="h%d-%d" % (k + 1, k + 1), t=k * 4.2, src="Appended line %d." % (k + 1),
                                                 dst="追加的第 %d 句。" % (k + 1), srcLang="en", dstLang="zh-CN"))
            i[0] += 1
            return i[0] < int(n)
        GLib.timeout_add(300, add)
        return {"ok": True}
    if cmd == "calls":
        if arg == "real":
            app.fake_calls = None
        elif arg in ("", "none"):
            app.fake_calls = {}
        else:
            app.fake_calls = dict(p.split("=", 1) for p in arg.split(","))
        return {"ok": True, "fakeCalls": app.fake_calls}
    if cmd == "realcalls":
        from ..core import meeting_end
        return {"ok": True, "calls": meeting_end.calls()}
    if cmd == "endtimes":
        app.end_times = None if arg in ("", "off") else tuple(float(x) for x in arg.split())
        return {"ok": True, "endTimes": app.end_times}
    if cmd == "endkeep":
        app.keep_recording()
        return {"ok": True}
    if cmd in ("notes-tab", "notes-search", "notes-wide"):
        app.show_notes()
        w = app.notes_window
        if cmd == "notes-tab":
            w.set_tab(arg)
        elif cmd == "notes-search":
            w.set_tab("transcript")
            w.search.set_text(arg)
        else:
            w.set_wide(arg == "on")
        return {"ok": True, "tab": w.tab, "wide": w.wide, "matches": len(w.matches), "match": w.match_index}
    if cmd == "rename":
        # `rename <id> <title>`; no title is 恢复自动标题.
        sid, _, title = arg.partition(" ")
        app.store.rename(sid, title)
        s = app.store.get(sid)
        from ..core import session_store
        return {"ok": s is not None, "title": s.title if s else None, "renamed": s.renamed if s else None,
                "shown": session_store.display_title(s) if s else None}
    if cmd == "delete":
        app.store.delete(arg)
        if app.store.get(arg) is None:
            app.folder_export.deleted(arg)
        return {"ok": True, "exists": app.store.get(arg) is not None, "live": app.store.live}
    if cmd == "notes-end":
        # The notes window's 结束: `ask`, then `keep` (继续记录) or `end` (结束会议).
        app.show_notes()
        w = app.notes_window
        {"ask": w._ask_end, "keep": lambda: w._end_answer(False), "end": lambda: w._end_answer(True)}[arg]()
        return {"ok": True, "asking": getattr(w, "confirm_end", False), "listening": listen.listening}
    if cmd == "notes-status":
        # How the notes window shows a state the network won't give on demand: `failed`, `invalidKey`…
        app.notes.status = arg
        app.changed()
        return {"ok": True, "status": app.notes.status}
    if cmd == "settings-scroll":
        app.show_settings()
        adj = app.settings_window.get_child().get_vadjustment()
        adj.set_value(float(arg) * (adj.get_upper() - adj.get_page_size()))
        return {"ok": True}
    if cmd == "settings-models":
        app.show_settings()
        app.settings_window._toggle_models(arg != "off")
        return {"ok": True}
    if cmd == "onboarding-step":
        app.show_onboarding()
        app.onboarding.go(int(arg))
        return {"ok": True, "step": app.onboarding.step if app.onboarding is not None else "done"}
    if cmd.startswith(("fix", "vocab")) or cmd in ("heard", "ask-names", "resettle", "word-list"):
        return _fixes(app, cmd, arg)
    if cmd in ("share", "unshare", "share-last", "shareSheet", "share-ui"):
        return _share(app, cmd, arg)
    if cmd == "quit":
        app.quit()
        return {"ok": True}
    return {"ok": False, "error": "unknown command " + cmd}


_share_last: dict = {}


def _share(app, cmd: str, arg: str) -> dict:
    """分享… (the Mac's share / unshare / shareSheet debug commands). The network runs on a thread:
    `share` and `unshare` answer at once, `share-last` says how the last one ended."""
    from ..core import share
    from . import share_dialog
    if cmd == "share-last":
        return {"ok": True, **_share_last}
    if cmd in ("share", "unshare"):
        p = arg.split(",")
        sid = p[0]
        s = app.store.get(sid)
        if s is None:
            return {"ok": False, "error": "no such record"}
        _share_last.clear()
        _share_last["running"] = cmd

        def run():
            c = share_dialog.client()
            if cmd == "unshare":
                r = share.ShareStore.read(sid)
                ok = r is not None and c.revoke(r, sid)
                Log.d("share: revoked %s" % ok)
                out = {"revoked": ok, "id": r.id if r else None}
            else:
                o = share.Options(scope="full" if "full" in p else "notes", password=share.make_password() if "pw" in p else None)
                res = c.share(s, o)
                out = {"kind": res.kind, "code": res.code, "hits": res.hits,
                       "lines": sorted(share.record_lines(res.hits, res.kept))}
                if res.record is not None:
                    out.update({"id": res.record.id, "url": res.record.url, "password": res.record.password})
                    Log.d("share: %s" % res.record.url)
            _share_last.clear()
            _share_last.update(out)
        threading.Thread(target=run, name="Share", daemon=True).start()
        return {"ok": True, "started": cmd}
    if cmd == "shareSheet":
        if not arg:
            if app.share_dialog is not None:
                app.share_dialog.close()
            return {"ok": True}
        s = app.store.get(arg)
        if s is None:
            return {"ok": False, "error": "no such record"}
        app.show_records()
        w = app.records_window
        w.selected = arg
        w.fill()
        return {"ok": True, **share_dialog.open_for(app, s, w).state()}
    # share-ui scope notes|full | days 7|30|365 | names|pw|summary on|off | options | go | strip | back | confirm
    #          | copy all|link|password | revoke | close | state
    d = app.share_dialog
    if d is None:
        return {"ok": False, "error": "no share dialog"}
    act, _, val = arg.partition(" ")
    if act == "scope":
        d.scope = val
    elif act == "days":
        d.days = int(val)
    elif act in ("names", "pw", "summary"):
        setattr(d, {"names": "names", "pw": "use_password", "summary": "summary"}[act], val == "on")
    elif act == "go":
        d.go()
    elif act == "strip":
        d.strip()
    elif act == "back":
        d.step = "settings"
    elif act == "confirm":
        d.confirm = True
    elif act == "options":
        d.show_options = True
    elif act == "copy" and d.record is not None:
        r = d.record
        d._copy({"link": r.url, "password": r.password or ""}.get(val) or d._message(r), val or "all")
    elif act == "revoke":
        d.revoke()
    elif act == "close":
        d.close()
        return {"ok": True}
    if act in ("scope", "days", "names", "pw", "summary", "back", "confirm", "options", "copy"):
        d.render()
    return {"ok": True, **d.state()}


def _fix_state(app, sid: str) -> dict:
    lines = app.store.lines(sid)
    every = [f for l in lines for f in l.fixes or []]
    return {"session": sid, "on": app.settings.fixMisheard, "askNames": app.settings.askNames,
            "applied": sum(1 for f in every if f.applied), "asked": sum(1 for f in every if f.ask),
            "off": sum(1 for f in every if f.off), "toast": app.fixes.toast_text(), "canUndo": app.fixes.can_undo,
            "asking": (lambda a: [a[1].from_, a[1].to, a[3]] if a else None)(app.fixes.asking(sid)),
            "pending": [[f.from_, f.to] for _l, f in app.fixes.pending(sid)],
            "lines": [{"id": l.id, "src": l.src, "shown": l.shown, "dst": l.dst,
                       "fixes": [f.to_json() for f in l.fixes]} for l in lines if l.fixes]}


def _fixes(app, cmd: str, arg: str) -> dict:
    """改正听错的词 (the Mac's fixes / heard / fixState / fixAnswer / fixLater / fixUndo / fixEdit /
    fixRevert / vocabAdd / vocabState / resettle):
      fixes on|off | ask-names on|off | heard <text>[|<translation>] (a finished sentence as if Ming heard it, in the
      meeting being listened to: the record, the fixing request, the notes window all follow) |
      fix-state [<id>] | fix-answer yes|no [<id>] | fix-later [<id>] | fix-undo | fix-revert <line> [<id>] |
      fix-edit <line>=<text>[|one][|keep0][|@<id>] | vocab-add Morpho=莫拉、莫法[|…] | vocab-remove <word> |
      vocab-state | fix-editor <line>=<text> (改这句… open in the records window) |
      word-list [import <text>|edit <word>|delete <word>] (设置 › 词表 on screen) |
      resettle <line>=<text> (the line heard again as <text>, then translated and fixed
      again with the lines after it in view)"""
    words = arg.split()
    fx = app.fixes

    def sid_at(i):
        return words[i] if len(words) > i else (app.store.live or (app.store.all()[0].id if app.store.all() else ""))
    if cmd == "fixes":
        app.settings.fixMisheard = arg != "off"
        app.settings.save()
        app.changed()
        return {"ok": True, "on": app.settings.fixMisheard}
    if cmd == "ask-names":
        app.settings.askNames = arg != "off"
        app.settings.save()
        return {"ok": True, "askNames": app.settings.askNames}
    if cmd == "heard":
        listen = app.listen
        if not listen.listening or listen.session_id is None:
            return {"ok": False, "error": "not listening"}
        from types import SimpleNamespace
        from ..core.translator import Heard
        lang = listen._main.hint or "zh-CN"
        seg = SimpleNamespace(start=listen.heard_seconds, seconds=2.0, index=0, voiceprint=None,
                              asked=app.settings.resolved_target(lang))
        # `heard <text>|<translation>`: a line Ming translated, the usual path (the fixing request
        # replaces its translation); without one, the path of a line Ming left untranslated.
        text, _, dst = arg.partition("|")
        heard = Heard(lang, text, dst or None)

        def run():
            listen._record(listen._main, seg, heard)
            app.changed()
        threading.Thread(target=run, daemon=True).start()
        return {"ok": True}
    if cmd == "resettle":
        line_id, _, text = arg.partition("=")
        sid = app.store.live
        line = app.store.line(sid, line_id) if sid else None
        if line is None:
            return {"ok": False, "error": "no such live line"}
        line.src = text
        app.store.replace(sid, line)
        fx.apply_known(line_id, sid)

        def run():
            dst = app.translator.translate(text, line.srcLang, line.dstLang, app.translator.SENTENCE)
            if dst:
                now = app.store.line(sid, line_id)
                now.dst = dst
                app.store.replace(sid, now)
        threading.Thread(target=run, daemon=True).start()
        return {"ok": True}
    if cmd == "fix-state":
        return {"ok": True, **_fix_state(app, sid_at(0))}
    if cmd == "fix-answer":
        sid = sid_at(1)
        a = fx.asking(sid) or next(((l, f, 1, 1) for l, f in fx.pending(sid)), None)
        if a is None:
            return {"ok": False, "error": "nothing waiting"}
        fx.answer(a[1], words[0] == "yes", sid)
        return {"ok": True, **_fix_state(app, sid)}
    if cmd == "fix-later":
        sid = sid_at(0)
        a = fx.asking(sid)
        if a is not None:
            fx.later(a[1], sid)
        return {"ok": a is not None, **_fix_state(app, sid)}
    if cmd == "fix-undo":
        fx.undo()
        return {"ok": True}
    if cmd == "fix-editor":
        # 改这句… open on a line of the record shown, with <text> typed in (the VM can't type Chinese).
        line_id, _, text = arg.partition("=")
        w = app.records_window
        if w is None or not w.get_visible():
            return {"ok": False, "error": "records window not shown"}
        w.edit_line(line_id, text or None)
        return {"ok": True}
    if cmd == "word-list":
        # 设置 › 词表 on screen: `word-list` scrolls to it; `word-list import <text>` opens 粘贴导入 with
        # <text> pasted ("|" for new lines); `word-list edit <word>` opens its spelling.
        app.show_settings()
        sw = app.settings_window
        wl = sw.word_list
        kind, _, rest = arg.partition(" ")
        if kind == "import":
            wl._import()
            wl.dialog_view.get_buffer().set_text(rest.replace("|", "\n"))
        elif kind == "edit":
            wl._edit(rest)
        elif kind == "heard":  # word-list heard <word>=<form>: typed into its 加一个容易听错的词
            word, _, form = rest.partition("=")
            t = next((t for t in app.vocabulary.snapshot() if t.word == word), None)
            if t is not None:
                wl._add_heard(t, form)
        elif kind == "delete":
            t = next((t for t in app.vocabulary.snapshot() if t.word == rest), None)
            if t is not None:
                wl._remove(t)

        def scroll():
            pos = sw.word_list_group.translate_coordinates(sw.scroll.get_child().get_child(), 0, 0)
            if pos:
                sw.scroll.get_vadjustment().set_value(max(0, pos[-1] - 12))
            return False
        GLib.timeout_add(200, scroll)
        return {"ok": True}
    if cmd == "fix-revert":
        sid = sid_at(1)
        line = app.store.line(sid, words[0]) if words else None
        f = next((f for f in (line.fixes or []) if f.applied), None) if line else None
        if f is None:
            return {"ok": False, "error": "no applied fix on that line"}
        fx.revert(f, line.id, sid)
        return {"ok": True, **_fix_state(app, sid)}
    if cmd == "fix-edit":
        line_id, _, rest = arg.partition("=")
        opts = rest.split("|")
        sid = next((o[1:] for o in opts[1:] if o.startswith("@")), None) or sid_at(99)
        n = fx.edit(line_id, sid, opts[0], everywhere="one" not in opts, remember="keep0" not in opts)
        return {"ok": n > 0, "changed": n, **_fix_state(app, sid)}
    if cmd == "vocab-add":
        r = app.vocabulary.import_text(arg.replace("|", "\n"))
        return {"ok": True, "added": r.added, "updated": r.updated, "skipped": r.skipped}
    if cmd == "vocab-remove":
        app.vocabulary.remove(arg)
        return {"ok": True}
    if cmd == "vocab-state":
        return {"ok": True, "path": app.vocabulary.path,
                "terms": [t.to_json() for t in app.vocabulary.snapshot()]}
    return {"ok": False, "error": "unknown command " + cmd}


def _voice(app, cmd: str, arg: str) -> dict:
    """我自己的声音 without a microphone: the network runs on a thread and `state` reads the result."""
    from ..core import voice_reference as vref
    from ..core import voices as voicemod
    from ..core.audio import PcmAudioSource, RATE, Wav
    sw = app.settings_window

    def refresh():
        if sw is not None and hasattr(sw, "_fill_voices"):
            sw._fill_voices()
    if cmd == "voice":
        lang, _, vid = arg.partition("=")
        if vid:
            app.settings.speakVoices[voicemod.key(lang)] = vid
            app.settings.save()
            refresh()
        Log.d("voice %s -> %s clone=%s" % (lang, app.speak.voice(lang), vref.exists()))
        return {"ok": True, "lang": lang, "chosen": (app.settings.speakVoices or {}).get(voicemod.key(lang)),
                "uses": app.speak.voice(lang), "options": [v for v, _n, _t in voicemod.voices(lang, app.ling.config())],
                "clone": vref.exists(), "clones": voicemod.clones(app.ling.config())}
    if cmd == "voice-clone":
        if arg == "off":
            if sw is not None:
                sw.remove_voice()
            else:
                vref.remove()
            return {"ok": True, "exists": vref.exists()}
        if arg in ("", "state"):
            out = {"ok": True, "exists": vref.exists(), "last": getattr(app, "voice_debug", None)}
            if vref.exists():
                out.update({"seconds": round(vref.duration(), 2), "textChars": len(vref.text() or ""), "slow": vref.saved_is_slow(),
                            "modes": [oct(os.stat(p).st_mode & 0o777) for p in (vref.folder(), vref.audio_path(), vref.text_path())]})
            return out
        app.voice_debug = {"running": True}

        def run():
            from .voice_clone import transcribe
            samples = vref.trim(Wav.read_file(arg))
            try:
                text = transcribe(app, samples)
            except Exception as e:  # noqa: BLE001
                app.voice_debug = {"running": False, "error": str(e)}
                return
            why = vref.check(samples, text)
            p = vref.pace(text, samples)
            if why is None:
                vref.save(samples, text)
            app.voice_debug = {"running": False, "seconds": round(len(samples) / RATE, 2), "textChars": len(text),
                               "pace": round(p, 2) if p else None, "why": why, "saved": why is None}
            GLib.idle_add(lambda: refresh() or False)
        threading.Thread(target=run, daemon=True).start()
        return {"ok": True, "started": True}
    if cmd == "voice-preview":
        code = arg or app.speak.target
        app.voice_debug = {"running": True}

        def play():
            from .room import Player
            from .settings_window import PREVIEW
            text = PREVIEW.get(code[:2], PREVIEW["en"])
            uses = app.speak.voice(code)
            start, n, first = time.monotonic(), 0, None
            out = Player(None)
            try:
                for pcm in app.speak.speech(text, code):
                    if first is None:
                        first = time.monotonic() - start
                    n += len(pcm)
                    out.write(pcm)
                out.drain()
                app.voice_debug = {"running": False, "voice": uses, "seconds": round(n / 2 / 24000, 2),
                                   "firstSound": round(first or 0, 2), "took": round(time.monotonic() - start, 2)}
            except Exception as e:  # noqa: BLE001
                app.voice_debug = {"running": False, "voice": uses, "error": str(e)}
            finally:
                out.close()
        threading.Thread(target=play, daemon=True).start()
        return {"ok": True, "started": True}
    if cmd == "voice-dialog":
        what, _, rest = arg.partition(" ")
        d = getattr(sw, "voice_dialog", None)
        if what == "open":
            app.show_settings()
            app.settings_window.record_voice()
            return {"ok": True}
        if d is None or d.window is None:
            return {"ok": False, "error": "no dialog"}
        r = d.recorder
        if what == "feed":  # the WAV as the microphone, in real time; the recording stops when it ends
            d.consent = True
            r.start(PcmAudioSource(rest))
        elif what == "finish":
            r.finish()
        elif what == "play":
            d.play(rest)
        elif what == "save":
            d.save()
        elif what == "close":
            d.close(False)
        return {"ok": True, "phase": r.phase, "why": r.why, "seconds": round(r.seconds, 1), "textChars": len(r.transcript),
                "playing": d.playing, "consent": d.consent}
    return {"ok": False, "error": "unknown command " + cmd}


def _ai(app) -> dict:
    """The AI service in use and what its last check found (never the key itself)."""
    c, ling = app.ling.config(), app.ling
    return {"provider": c.provider.id, "base": c.base, "hearBase": c.hear_url, "text": c.text_model, "hear": c.hear_model, "voice": c.voice_model,
            "state": ling.key_state, "hears": ling.hears, "check": ling.check_result.summary(), "message": ling.message(),
            "proxyLine": ling.check_result.proxy_line(ling.service_name, ling.service_host),
            "keyWorks": app.key_works, "asking": getattr(app, "_asking", None) is not None,
            "lastVoice": list(ling.last_voice) if ling.last_voice else None, "simulate": ling.simulate,
            "catalog": [len(ling.text_catalog), len(ling.hear_catalog)], "keyFile": os.path.basename(app.key.path),
            "notes": {"apart": c.notes_apart, "base": c.for_notes.base, "model": c.for_notes.text_model,
                      "ownKey": ling.notes_has_own_key, "catalog": len(ling.notes_catalog)},
            "customOnly": app.settings.aiCustomOnly, "googleOff": app.translator.google_off,
            "sentencesUntranslated": app.translator.sentences_untranslated}
