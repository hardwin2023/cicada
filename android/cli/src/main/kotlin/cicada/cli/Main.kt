// cicada-cli: the Android engines without Android (scripts/cli.sh runs it).
//
//   cicada-cli test                       the unit tests (no network)
//   cicada-cli listen <file.wav> [--target zh-CN] [--speed 1|0] [--notes] [--log] [--room]
//       Plays the file into ListenEngine as if the phone were playing it, prints each line as it
//       is recorded, then the record's folder. --notes waits for the final notes and prints them.
//   cicada-cli hear <file.wav> [--target zh-CN]   one file to the hear model (Ming on Ling), raw reply printed
//   cicada-cli say <file.wav> [--to en] [--out said.wav]
//       我说 · 面对面: what I say heard and translated, then read by the service's voice into a WAV
//   cicada-cli speak <text> [--voice US_Emma] [--lang ja] [--out speak.wav]   one line in the service's voice
//       --reference <wav> [--own zh-CN]: in the voice of that recording (我自己的声音), checked first
//   cicada-cli segments <file.wav> [--room]  where the segmenter cuts (--room: 面对面's gate)
//   cicada-cli roundtrip <session.json>…  reads and writes records, says if a byte changed
//
//   --provider ling|openrouter|zenmux   the AI service (default ling), with its recommended models;
//   --hear-model <id>                   another hear model on it
//
// Records go to CICADA_HOME (default: a temp folder). The key comes from CICADA_KEY_FILE, else the
// Mac app's dev or release key file for the service; it is never printed.
package cicada.cli

import cicada.*
import java.io.File
import kotlin.system.exitProcess

val resources: File = File(System.getProperty("cicada.resources") ?: "../Resources")

fun loadStrings(ui: String) = Strings.load(ui) { rel ->
    val mac = File(resources, rel)
    val android = File(System.getProperty("cicada.androidStrings") ?: "app/src/main/strings", rel)
    when {
        rel.endsWith("Android.strings") && android.isFile -> android.readText()
        mac.isFile -> mac.readText()
        else -> null
    }
}

fun macKeyFile(service: String = "ling"): File? = System.getenv("CICADA_KEY_FILE")?.let(::File)
    ?: listOf("LiveSubs Dev", "LiveSubs").map { File(System.getProperty("user.home"), "Library/Application Support/$it/" + Paths.keyFile(service).name) }.firstOrNull { it.isFile }

/// The AI service the settings name, with the Mac's key file for it.
fun client(settings: AppSettings) = LingClient(AIKey(PlainProtector, macKeyFile(settings.aiProvider)), config = settings::aiConfig)

fun main(argv: Array<String>) {
    val args = argv.toList()
    if (args.isEmpty()) { println("usage: cicada-cli test|listen|hear|segments|roundtrip …"); exitProcess(2) }
    fun opt(name: String, fallback: String) = args.indexOf(name).let { if (it >= 0 && it + 1 < args.size) args[it + 1] else fallback }
    loadStrings(opt("--ui", "zh-Hans"))
    val service = opt("--provider", "ling")
    val hearModel = opt("--hear-model", "")
    fun settings(target: String = "zh-CN") = AppSettings(target = target, aiProvider = service).apply {
        if (hearModel.isNotEmpty()) aiHearModels[service] = hearModel
    }
    when (args[0]) {
        "test" -> exitProcess(Tests.run())
        "segments" -> {
            val pcm = Wav.read(File(args[1]).inputStream())
            val list = mutableListOf<Segment>()
            val seg = Segmenter(if ("--room" in args) VoiceGate() else null).apply { onSegment = { list.add(it) } }
            var i = 0
            while (i < pcm.size) { seg.feed(pcm.copyOfRange(i, minOf(pcm.size, i + 1600))); i += 1600 }
            seg.flush()
            for (s in list) println("%3d %7.2fs %5.2fs".format(s.index, s.start, s.seconds))
            println("${list.size} segments, ${"%.1f".format(list.sumOf { it.seconds })}s of speech")
        }
        "roundtrip" -> {
            var changed = 0
            for (path in args.drop(1).filter { !it.startsWith("--") }) {
                val original = File(path).readText()
                val session = Session.read(original)
                val written = session?.let { Json.write(it.toJson()) }
                val same = written == original
                if (!same) changed++
                println("${if (same) "same   " else "CHANGED"} $path (${session?.lines?.size ?: 0} lines${if (session?.notes == null) "" else ", notes"})")
                if (!same && args.contains("--diff") && written != null) {
                    val a = original.lines(); val b = written.lines()
                    val at = a.indices.firstOrNull { it >= b.size || a[it] != b[it] } ?: a.size
                    println("  first difference at line ${at + 1}:\n  mac:     ${a.getOrNull(at)}\n  android: ${b.getOrNull(at)}")
                }
            }
            exitProcess(if (changed == 0) 0 else 1)
        }
        "hear" -> {
            val ling = client(settings())
            val target = opt("--target", "zh-CN")
            val reply = ling.chat(Translator.hearPrompt(target, null, emptyList()), Translator.hearInstruction(target), Priority.Translate,
                                  maxTokens = 800, timeout = 20.0, model = ling.config().hearModel, audio = Wav.bytes(Wav.read(File(args[1]).inputStream())))
            println(reply)
            println("-> ${Translator.parseHeard(reply, target, null)}")
        }
        "say" -> {
            Log.echo = args.contains("--log")
            val ling = client(settings())
            val to = opt("--to", "en")
            val pcm = Wav.read(File(args[1]).inputStream())
            val started = System.currentTimeMillis()
            val heard = Translator(ling).hear(Clip.wav(pcm), to, null, pcm.size / Segmenter.RATE.toDouble())
            val line = TranscriptLine(speaker = "me", src = heard?.original ?: "", dst = heard?.translation, srcLang = heard?.lang ?: "", dstLang = to)
            val text = ListenEngine.speakable(line)
            println("heard ${heard?.lang}: ${heard?.original}\n   -> $text (${System.currentTimeMillis() - started} ms)")
            if (text == null) { println("nothing to say (not translated)"); exitProcess(1) }
            if (!ling.speaks) { println("${ling.provider.name} has no voice here: the phone's would read it"); exitProcess(0) }
            val out = java.io.ByteArrayOutputStream()
            val t = System.currentTimeMillis()
            var first = 0L
            ling.speech(text) { if (first == 0L) first = System.currentTimeMillis() - t; out.write(it) }
            val bytes = out.toByteArray()
            val samples = ShortArray(bytes.size / 2) { ((bytes[2 * it].toInt() and 0xff) or (bytes[2 * it + 1].toInt() shl 8)).toShort() }
            val file = File(opt("--out", "said.wav"))
            file.writeBytes(Wav.bytes(samples, LingClient.TTS_RATE))
            println("voice ${ling.config().voiceModel}: %.1f s of audio, first sound after %d ms, all in %d ms -> %s".format(
                samples.size / LingClient.TTS_RATE.toDouble(), first, System.currentTimeMillis() - t, file.path))
            exitProcess(0)
        }
        "speak" -> {
            // speak <text> [--voice US_Emma] [--lang ja] [--out speak.wav]: one line in a service voice.
            Log.echo = args.contains("--log")
            val ling = client(settings())
            val voice = opt("--voice", "").ifEmpty { null }
            val lang = opt("--lang", "").ifEmpty { null }
            // --reference <wav> [--own zh-CN]: the user's own voice, the recording checked as 录制 checks it.
            val reference = opt("--reference", "").ifEmpty { null }?.let { path ->
                val pcm = Wav.read(File(path).inputStream())
                when (val r = VoiceReference.check(Translator(ling), pcm, opt("--own", "zh-CN"))) {
                    is VoiceReference.Check.Ok -> {
                        // What 用这个声音 keeps: the trimmed clip, written and read back as the app does.
                        println("reference: %.1f s recorded, %.1f s kept, heard %d characters".format(pcm.size / 16000.0, r.pcm.size / 16000.0, r.text.length))
                        VoiceReference.save(r.pcm, r.text)
                        VoiceReference.reference()!!
                    }
                    is VoiceReference.Check.Again -> { println("reference refused: ${Strings.LF(r.reason, *r.args.toTypedArray())}"); exitProcess(1) }
                }
            }
            val out = java.io.ByteArrayOutputStream()
            val t = System.currentTimeMillis()
            var first = 0L
            ling.speech(args[1], voice, lang, reference = reference) { if (first == 0L) first = System.currentTimeMillis() - t; out.write(it) }
            val bytes = out.toByteArray()
            val samples = ShortArray(bytes.size / 2) { ((bytes[2 * it].toInt() and 0xff) or (bytes[2 * it + 1].toInt() shl 8)).toShort() }
            val file = File(opt("--out", "speak.wav"))
            file.writeBytes(Wav.bytes(samples, LingClient.TTS_RATE))
            println("voice ${ling.config().voiceModel} ${voice ?: "-"}: %.1f s of audio, first sound after %d ms, all in %d ms -> %s".format(
                samples.size / LingClient.TTS_RATE.toDouble(), first, System.currentTimeMillis() - t, file.path))
            exitProcess(if (samples.isEmpty()) 1 else 0)
        }
        "listen" -> {
            Log.echo = args.contains("--log")
            val settings = settings(opt("--target", "zh-CN"))
            val ling = client(settings)
            if (!ling.hasKey) { println("no $service key (set CICADA_KEY_FILE)"); exitProcess(2) }
            val store = SessionStore()
            val notes = NotesEngine(ling, store)
            val engine = ListenEngine(ling, Translator(ling), store, notes, settings)
            val shown = HashMap<String, String>()
            val started = System.currentTimeMillis()
            engine.onChange {
                val id = engine.sessionId ?: return@onChange
                synchronized(shown) {
                    for (l in store.lines(id)) {
                        val text = "${l.src}\n${" ".repeat(17)}→ ${l.dst ?: "…"}"
                        if (shown[l.id] == text) continue
                        val tag = if (shown.containsKey(l.id)) "upd" else "new"
                        shown[l.id] = text
                        println("[%5.1f] %s %s %-5s %s".format((System.currentTimeMillis() - started) / 1000.0, tag, Languages.clock(l.t), l.srcLang, text))
                    }
                }
            }
            val ended = java.util.concurrent.CountDownLatch(1)
            val source = PcmAudioSource(File(args[1]), opt("--speed", "1").toDouble())
            source.onEnded = { ended.countDown() }
            engine.start(source, if ("--room" in args) "mic" else "file")
            ended.await()
            Thread.sleep(1500)
            engine.stop()
            val id = engine.sessionId!!
            if (args.contains("--notes")) {
                for (i in 0 until 120) { if (store.get(id)?.notes?.final == true) break; Thread.sleep(1000) }
            }
            store.flush()
            val record = store.get(id)
            println("\n${record?.lines?.size ?: 0} lines in ${File(Paths.sessions, id)}")
            record?.notes?.let { n ->
                println("notes${if (n.final) " (final)" else ""}: ${n.title}\n  ${n.summary}")
                for (t in n.topics) println("  ${Languages.clock(t.start)} ${t.title}: ${t.points.joinToString(" / ")}")
                for (t in n.todos) println("  [ ] ${t.text} (${t.owner})")
            }
            exitProcess(0)
        }
        else -> { println("unknown command ${args[0]}"); exitProcess(2) }
    }
}
