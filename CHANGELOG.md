# Changelog

One section per release, newest first; one version covers every platform. `scripts/release.sh`
writes it from the `feat:` and `fix:` commits since the last tag, grouped by platform (the commit's
scope), and the release workflow publishes it as the release notes. Since 1.1.2 every release ships
every platform (one with nothing new says No changes); earlier ones shipped only those listed. Lines under `## Unreleased` become the release's summary. The Chinese changelog for users is `site/changelog.json`.

## 1.10.0 — 2026-11-14

### Mac

#### New

- Remember known voices across meetings ([9a17476](https://github.com/wquguru/cicada/commit/9a17476dca1707d0770ce10d1f7eb9c8a65b321d))
- Open the room microphone when the user starts a meeting ([0d9296c](https://github.com/wquguru/cicada/commit/0d9296cdc4ceaa4378a5c476d90ccd77064f2e8d))
- Re-transcribe a saved meeting from its recording ([fa85ed5](https://github.com/wquguru/cicada/commit/fa85ed57786465f6692a5409cf14c826e42db285))
- Option to label a speaker on every line ([dbff738](https://github.com/wquguru/cicada/commit/dbff73887aa73670e5c30acc061b132c4646a959))
- Edit meeting notes and build a people library ([a777554](https://github.com/wquguru/cicada/commit/a7775544167d9ea4afa5ced53a771269894c2a77))
- Name a voice from its transcript tag ([fc143e8](https://github.com/wquguru/cicada/commit/fc143e8d2a772acd1112948c26d9a73496992d2f))
- Copy Notes and Copy Everything paste into document apps with headings, lists and the fishbone as a picture ([d8471f7](https://github.com/wquguru/cicada/commit/d8471f73e3d765c08bfdbae1e09f062aa3c19905))
- Right-click a fishbone to copy it as an image or as text ([2647a9d](https://github.com/wquguru/cicada/commit/2647a9da9cd9f47cb676e3bdac1fd69222291758))
- Click a finished meeting's summary, a conclusion or a to-do to fix it in place ([c8b0952](https://github.com/wquguru/cicada/commit/c8b09526c1ad6eabf62404b362ca7b9fa173bb87))

#### Fixed

- Require 6 seconds of speech before enrolling ([b429a0e](https://github.com/wquguru/cicada/commit/b429a0ef6b38eed6f301f61e5db2fca3556cb46f))
- Start auto in the Mac language, not English ([9260692](https://github.com/wquguru/cicada/commit/926069280f490d2f60bee1d18e2e7eca2e224e71))
- Hear your own voice and name a one-to-one caller ([2f1c939](https://github.com/wquguru/cicada/commit/2f1c9396b86621f0cc3ec511826e1bf767246862))
- Keep a one-to-one voice nameable past a stray cluster ([738e6ac](https://github.com/wquguru/cicada/commit/738e6ac3011bc04f72c1b93d64f8f7f9db74874c))
- Your own voice no longer comes out silent when the recording ends in a pause ([cad2453](https://github.com/wquguru/cicada/commit/cad2453273efcca39d4a20507e69b22679aeb4a5))

### Windows

#### New

- Interpreting can speak in your own voice: record 15 seconds and the meeting hears your translation in it (#32) ([29cf959](https://github.com/wquguru/cicada/commit/29cf959d69f6aef75a5074dc78a7411ee8544198))

#### Fixed

- The cloned voice no longer comes out silent when the recording ends in a pause ([920c82f](https://github.com/wquguru/cicada/commit/920c82f3408d3750121779123156a31e4e898587))

### Android

#### New

- In person can read your translated words in your own voice, cloned from a 10–15 s recording with a Ling key ([3a993c0](https://github.com/wquguru/cicada/commit/3a993c00c04142e975bde653ca1f8687c48cab0d))

#### Fixed

- Face to face now hears people speaking normally across the table, not only someone right at the phone ([415b092](https://github.com/wquguru/cicada/commit/415b092b62e92ede7912b9120abf3cddb5815b76))
- In person reads your words in a voice you choose for each language, including Ming's with a Ling key ([341afdf](https://github.com/wquguru/cicada/commit/341afdf459655d1260441bc19eeef6c5c7db3766))
- Your own voice no longer comes out cut short when the recording ends in a pause ([29b5714](https://github.com/wquguru/cicada/commit/29b57142a65710f110de53dff6d78f4a9f0b1e62))

### Linux

#### New

- Interpreting can speak in your own voice: record 10–15 s in Settings and the room hears the translation in it ([ae02317](https://github.com/wquguru/cicada/commit/ae02317c5144b3510648f3b1d7decedfc416b2aa))

## 1.9.0 — 2026-11-12

### Mac

#### New

- While a recording plays back, the whole line being played lights up and a click anywhere on a line plays from there ([4e0aa4f](https://github.com/wquguru/cicada/commit/4e0aa4f7685ed57cbaf0ded0d684afade8f4d904))
- Notes can use their own model, or another OpenAI-compatible service with its own address and key ([21642b9](https://github.com/wquguru/cicada/commit/21642b9bf74e0623d6bdbaee9cb04b150f5c8b3e))
- Interpreting can run hands-free: while Cicada listens to a meeting, just start talking and the translation goes out after a one-second pause ([a44d0e8](https://github.com/wquguru/cicada/commit/a44d0e8b8abdabe8bf6445ab1f4adaf8303555ca))
- After each meeting, notes and transcript can be saved as Markdown into a folder you pick, such as an Obsidian vault ([3b48808](https://github.com/wquguru/cicada/commit/3b488088d89396d851520db7d1dfa8ac8711787f))

#### Fixed

- A short reply in a voice not yet known no longer joins the answer before it in the live transcript ([ab787d4](https://github.com/wquguru/cicada/commit/ab787d4ad960da95b62e0fc4cf9731b15948cc4d))
- The meeting record no longer moves a word from one speaker's sentence into the next speaker's line ([4cb8512](https://github.com/wquguru/cicada/commit/4cb8512b0d2b587a16b30046198bf57462bcee3b))
- What you say with the talk key while the other side talks is no longer dropped as silence ([3c6bb56](https://github.com/wquguru/cicada/commit/3c6bb56db093f30ddf595500f3ae6a022dab280c))
- Cicada no longer quits when a speech model starts downloading as listening begins ([91e1cda](https://github.com/wquguru/cicada/commit/91e1cda8cc24584828385af0192dc082ba01ec2f))
- With the mic on in a hybrid meeting, the talk key now works while the other side is talking ([bc82c12](https://github.com/wquguru/cicada/commit/bc82c1242a21592f64c8644f53707136fcc4728e))
- Other apps hear the built-in mic again while Interpreting is on ([4cbc0a1](https://github.com/wquguru/cicada/commit/4cbc0a19c12bcf148eb38017ea5291d6955a98f0))
- With a meeting language picked by hand, people in the room speaking your language are recognized once you turn on the mic ([648f273](https://github.com/wquguru/cicada/commit/648f273b0d91a2502a54ced13d32e05e09810433))
- In Dark Mode, text and checkboxes no longer turn white on Cicada's white cards ([3e2cb86](https://github.com/wquguru/cicada/commit/3e2cb8687fff21713760a78e1cbeace55132eb66))
- Imported recordings and videos, and re-transcribed meetings, now tell speakers apart too ([3a97dab](https://github.com/wquguru/cicada/commit/3a97dab9043090ce40a91a446f9968e2c4e0f6f1))
- A custom AI service whose key fails is named by its address, not "The this service key doesn't work" ([abe84d2](https://github.com/wquguru/cicada/commit/abe84d23d8b1359f1596202967ff08230946a7b1))
- A click on the words of a transcript line plays the recording from there, and the play button comes back when it ends ([7c11a14](https://github.com/wquguru/cicada/commit/7c11a14dc8975d32ce76cb43ab70ea8c97262e7f))
- Cicada no longer quits now and then when the menu bar panel opens ([9d3286e](https://github.com/wquguru/cicada/commit/9d3286eba8baba72973c14d7e7b807c50aea61eb))
- Cicada no longer quits after an interpreted sentence when the meeting plays from the speakers ([1c3d014](https://github.com/wquguru/cicada/commit/1c3d0142e4c2ad874c35c38f24733980ac8ca5e7))
- While a meeting is listened to, the talk key hears you from the moment you press it and no longer sends the meeting's own words ([872a570](https://github.com/wquguru/cicada/commit/872a570659d2dae6dae576dd8dd1f87c0dc831fd))
- Interpreting no longer speaks a bare heading like "翻译结果：" into the meeting ([f53c136](https://github.com/wquguru/cicada/commit/f53c13637a08aa94af52c469f4d19b32b30f0c86))

### Windows

#### New

- While a recording plays back, the whole line being played lights up and a click anywhere on a line plays from there ([5904907](https://github.com/wquguru/cicada/commit/59049078d486dd31849b927bc4d76215f585f0ca))
- Notes can use their own model, or another OpenAI-compatible service with its own address and key ([5acd003](https://github.com/wquguru/cicada/commit/5acd003b144ddbfc1e659fc383a9ba05b78aef32))
- After each meeting, notes and transcript can be saved as Markdown into a folder you pick, such as an Obsidian vault ([bd1ccb6](https://github.com/wquguru/cicada/commit/bd1ccb6041037ea25891e901f76b21bf9a453fca))

#### Fixed

- Installing VB-Cable no longer leaves the computer silent ([a3aa981](https://github.com/wquguru/cicada/commit/a3aa981a4a7c6f450631091da220c60e3a45cc03))
- The talk key now sends what you say while the other side talks on the speakers ([6ca73c8](https://github.com/wquguru/cicada/commit/6ca73c83e9677e0e5d5f1e8a0ade71323f8c1e34))
- A custom AI service whose key fails is named by its address in the tray and notes window ([933d596](https://github.com/wquguru/cicada/commit/933d596be41d19aa83962f42ff1863ca5dd9be86))
- Interpreting no longer speaks a bare heading like "翻译结果：" into the meeting ([598ea2c](https://github.com/wquguru/cicada/commit/598ea2c87cfca60b2d984946007775963344898b))

### Android

#### New

- While a recording plays back, the whole line being played lights up and the list follows it until you scroll away ([f6187ba](https://github.com/wquguru/cicada/commit/f6187ba2b1bd1bbb7e1f50af7a89280509b26040))
- Notes can use their own model, or another OpenAI-compatible service with its own address and key ([49ad404](https://github.com/wquguru/cicada/commit/49ad40493cafcee1d0d58ca0b5e355198f8caea2))
- After each meeting, notes and transcript can be saved as Markdown into a folder you pick ([7f22d77](https://github.com/wquguru/cicada/commit/7f22d77beb2d7de9857aed14ed3f39423042223a))

#### Fixed

- Imported recordings and videos show who said each line ([c6ece7c](https://github.com/wquguru/cicada/commit/c6ece7cdc8dd554a68b5cc022193e9dc7bbc6900))
- A custom AI service whose key fails is named by its address on the AI card and notification ([ba25b10](https://github.com/wquguru/cicada/commit/ba25b10bd5c981faf377e2760cdff8bee24607be))
- Interpreting no longer speaks a bare heading like "翻译结果：" into the meeting ([2bb0834](https://github.com/wquguru/cicada/commit/2bb0834ffbdd029fd8ef129274f0fd64dad405a5))

### Linux

#### New

- While a recording plays back, the whole line being played lights up and a click anywhere on a line plays from there ([fba3a7a](https://github.com/wquguru/cicada/commit/fba3a7afe4bd9cbd67b6bc390448b69a11c1754d))
- Notes can use their own model, or another OpenAI-compatible service with its own address and key ([5f26aea](https://github.com/wquguru/cicada/commit/5f26aea53cf680beaec59bdc83909ccb1d1d0ae1))
- After each meeting, notes and transcript can be saved as Markdown into a folder you pick, such as an Obsidian vault ([48a0af4](https://github.com/wquguru/cicada/commit/48a0af4c946593b084f6606b731f459919edfc30))

#### Fixed

- What you say with the talk key while the other side is talking is sent instead of dropped ([1a1a5eb](https://github.com/wquguru/cicada/commit/1a1a5eb079e4d06573851e50ba8dc7d8c1fccf0a))
- In a dark desktop theme, the live notes window's status line and its button are readable again ([184739a](https://github.com/wquguru/cicada/commit/184739a1b176879a5a723d1d997e0423bb7269bd))
- Imported records that tell speakers apart show who said each line ([83379f6](https://github.com/wquguru/cicada/commit/83379f6771e36470819a637b835c489a8cdf4259))
- A custom AI service whose key fails is named by its address in the tray, notification and notes window ([9458abb](https://github.com/wquguru/cicada/commit/9458abb39fa4f31ee183a7f9a03d1cc171fe989f))
- Interpreting no longer speaks a bare heading like "翻译结果：" into the meeting ([13e9591](https://github.com/wquguru/cicada/commit/13e95912813ad11dac2481538b610045ae7c30d2))

## 1.8.0 — 2026-11-09

### Mac

#### New

- Choose the microphone used for room meetings ([981f00a](https://github.com/wquguru/cicada/commit/981f00a70181918345aa8682d0d7ffb37abb5380))
- Pick which microphone hears the room from the arrow beside Turn on mic ([1701241](https://github.com/wquguru/cicada/commit/170124157bb83f436ce28c5586ceda98862fe471))

#### Fixed

- Fixing misheard words no longer turns a Chinese word into its English translation, or changes letters inside an English word ([2ef62fc](https://github.com/wquguru/cicada/commit/2ef62fc1ce4c9fd8f409d026aeea24a8a25f14d7))
- A name the notes got wrong no longer spreads into translations and later fixes, and a name said again and again stays its own term ([09b3b3d](https://github.com/wquguru/cicada/commit/09b3b3d9b9577ea0ee070f5e3a49e90f9a818acd))
- The microphone menus no longer list the speakers or a VPAUAggregateAudioDevice while echo cancellation runs ([07ed4c0](https://github.com/wquguru/cicada/commit/07ed4c052ec26315dd69fea64385bb4ca1a5f42a))

### Windows

#### New

- Keyboards without right Ctrl can pick another talk key in Settings › Interpreting ([994dd23](https://github.com/wquguru/cicada/commit/994dd23faf3a99e8909202939a79d2aa3efdae6a))

#### Fixed

- Fixing misheard words no longer turns a Chinese word into its English translation, or changes letters inside an English word ([9ac1feb](https://github.com/wquguru/cicada/commit/9ac1feb789feb297ec41c354ff9cab35d029f662))
- A name the notes got wrong no longer spreads into translations and later fixes, and a name said again and again stays its own term ([dace10e](https://github.com/wquguru/cicada/commit/dace10e3bc35bbb0a2504d0418d7f56d3b58fc78))
- Preview says why no sound played, and a Windows voice the PC doesn't have is no longer picked ([3c8c9fd](https://github.com/wquguru/cicada/commit/3c8c9fd64ad1430b7e82d4e1bdc7e6a3562a646d))

### Android

#### Fixed

- Fixing misheard words no longer turns a Chinese word into its English translation, or changes letters inside an English word ([6d13b5c](https://github.com/wquguru/cicada/commit/6d13b5c75007fc4e1ddd8cb76a0d66cc180c48c7))
- A name the notes got wrong no longer spreads into translations and later fixes, and a name said again and again stays its own term ([64710de](https://github.com/wquguru/cicada/commit/64710de2f747a70560edd4e7a0fedb4ffb6e2be0))

### Linux

#### Fixed

- Fixing misheard words no longer turns a Chinese word into its English translation, or changes letters inside an English word ([ee60b86](https://github.com/wquguru/cicada/commit/ee60b8663d4c8d9171e21b5d9297474b53511499))
- A name the notes got wrong no longer spreads into translations and later fixes, and a name said again and again stays its own term ([3bd0057](https://github.com/wquguru/cicada/commit/3bd005738f7aafae305d77bea43cb8fad302103e))

## 1.7.0 — 2026-11-08

### Mac

#### New

- Cicada stays in the Dock while it runs, with an orange dot while recording and a right-click menu ([308f00c](https://github.com/wquguru/cicada/commit/308f00c27dfe008f3ccea3dbb22a58e482b5026e))
- Share… copies the link and password together as one message in the app's language ([64b9471](https://github.com/wquguru/cicada/commit/64b94712a1ef3d9b9049e062db0a4952e45b6974))

#### Fixed

- A fresh 7-day share link no longer says it lasts 8 days ([a67e9c7](https://github.com/wquguru/cicada/commit/a67e9c72ba1a20e18c81b7ce291c03b04aa4f5ce))
- Fast speech without pauses comes out one sentence or clause per line instead of one growing block (#20) ([93dfb07](https://github.com/wquguru/cicada/commit/93dfb075e933fa3903378fb8b3caafd0a462ecd4))
- The live notes transcript starts a new paragraph every two or three sentences when someone talks fast ([7c40e6b](https://github.com/wquguru/cicada/commit/7c40e6b11301246680e85f22016033945cdd1e3e))
- The meeting record no longer splits a Chinese word like 所以 across two lines ([ac4d8e0](https://github.com/wquguru/cicada/commit/ac4d8e0929f153c68fae78435ddcfd8de073475a))
- In the live notes window, fast Chinese lines end at a clause more often instead of between two words ([79af264](https://github.com/wquguru/cicada/commit/79af264913a67bb50123788d92eaac4fb24d7ba4))

### Windows

#### New

- Share… copies the link and password together as one message in the app's language ([b01fe7f](https://github.com/wquguru/cicada/commit/b01fe7fc59215e1f708f61c687434244e4600947))

### Android

#### New

- Share… copies the link and password together as one message in the app's language ([3ba3243](https://github.com/wquguru/cicada/commit/3ba32437b8933d3d22265528ee7a82909d056647))

### Linux

#### New

- Share… copies the link and password together as one message in the app's language ([46e82e2](https://github.com/wquguru/cicada/commit/46e82e203398f24b929535594f936828c42ccf66))

#### Fixed

- Cicada stays in the dock while it runs, so it can be found during a meeting ([7b14308](https://github.com/wquguru/cicada/commit/7b1430864cc54ccc71a3ac414a1191bcdef94c0a))

### Website

- A shared meeting opens on its notes, and each chapter's dialogue, the speakers and the original text appear when asked for ([d231fc8](https://github.com/wquguru/cicada/commit/d231fc8c5db2296061c053fd2d3d5799478f5655))
- A shared meeting with one speaker or one line says 1 person and 1 line in English ([e1efbe8](https://github.com/wquguru/cicada/commit/e1efbe830888d3d4ca2aacbf9054e9b4fd36dc2e))

## 1.6.1 — 2026-11-08

### Mac

#### Fixed

- With the microphone open, the meeting recording keeps your own voice too (#19) ([a4ecf97](https://github.com/wquguru/cicada/commit/a4ecf97be0c7c70561074b8c79cb298bc5fcebfa))

### Windows

#### Fixed

- With the microphone open, the meeting recording keeps your own voice too (#19) ([677d2c7](https://github.com/wquguru/cicada/commit/677d2c756e5ea3869c78ffc7acd3f20f87a5e0b6))

### Android

No changes; released to keep every platform on the same version.

### Linux

#### Fixed

- With the microphone open, the meeting recording keeps your own voice too (#19) ([5e78010](https://github.com/wquguru/cicada/commit/5e780105a1054d205a0399b78b8d3462e4894088))

### Website

- Text aimed at the sensitive-content check can't talk a key past it ([a79094b](https://github.com/wquguru/cicada/commit/a79094be72de9511a0d12e8d72f761c9c5ac8044))
- Share limits count an IPv6 household as one visitor, and the whole site has a daily review budget ([952a170](https://github.com/wquguru/cicada/commit/952a170d8900887404f2a8c030518f6eb9224b95))
- A password link locked by wrong guesses opens again after 24 hours ([d510067](https://github.com/wquguru/cicada/commit/d51006756b40234cca87f17dbba928358938ea74))
- The sensitive-content check tries Cloudflare's Clef before Jev, which ZenMux refuses for mainland China ([4168864](https://github.com/wquguru/cicada/commit/4168864a3c2df185784b96b5749e276460c1e9c2))

## 1.6.0 — 2026-11-08

### Mac

#### New

- Share a meeting as a link (Share…), checked for keys and other sensitive content before upload ([062f20f](https://github.com/wquguru/cicada/commit/062f20fd27259305a5cef48b0cdf3f5c422f199e))

#### Fixed

- Corrected words under Names and terms in the notes window no longer swap places every second ([b4215c5](https://github.com/wquguru/cicada/commit/b4215c5f64e95d57d7fe17e0e5cd8d874195910f))
- Names and terms in the notes keep their place when the notes update ([e7a9735](https://github.com/wquguru/cicada/commit/e7a9735e2b674aa885eb5d2663868a8b7d03264e))

### Windows

#### New

- Share a meeting as a link, checked for keys and other sensitive content before upload ([ad6b596](https://github.com/wquguru/cicada/commit/ad6b596162f286505da464f2588bdae21abcc501))

#### Fixed

- Names and terms in the notes keep their place when the notes update ([e7a9735](https://github.com/wquguru/cicada/commit/e7a9735e2b674aa885eb5d2663868a8b7d03264e))

### Android

#### New

- Share a meeting as a link, checked for keys and other sensitive content before upload ([d9bb01d](https://github.com/wquguru/cicada/commit/d9bb01d0b902b6ed4fd53cef46a681d763cd693e))

#### Fixed

- Names and terms in the notes keep their place when the notes update ([e7a9735](https://github.com/wquguru/cicada/commit/e7a9735e2b674aa885eb5d2663868a8b7d03264e))

### Linux

#### New

- Share a meeting as a link, checked for keys and other sensitive content before upload ([117a735](https://github.com/wquguru/cicada/commit/117a7351abfccd4ebc1af0aced0356fed4c84b48))

#### Fixed

- Names and terms in the notes keep their place when the notes update ([e7a9735](https://github.com/wquguru/cicada/commit/e7a9735e2b674aa885eb5d2663868a8b7d03264e))

### Website

- Shared meetings open as a page on cicada.indaloop.app, with a password page and link previews ([b278300](https://github.com/wquguru/cicada/commit/b278300c34f3d3ba1e84156b1eeaf6a5512e9696))

## 1.5.1 — 2026-11-07

### Mac

#### New

- Misheard names and terms are fixed in subtitles and live notes as the meeting goes, with new names asked about once ([bf9a680](https://github.com/wquguru/cicada/commit/bf9a680258c0148f9c8f1958b84018512a5826da))
- Settings › Word list keeps the spellings you use, and takes many at once by pasting ([d087810](https://github.com/wquguru/cicada/commit/d0878107672ed193dccd869de31eec4321a292e0))
- Fix a misheard word yourself from the meeting record, settle waiting fixes after the meeting, and undo any fix ([b6f1f8c](https://github.com/wquguru/cicada/commit/b6f1f8ccd92e5dd164706a0ee3e7da8ac4f322ea))
- Settings › Word list edits in place: change a spelling, add or remove a misheard form, undo a delete, see counts before pasting ([d7db66f](https://github.com/wquguru/cicada/commit/d7db66fdd81cfe5b14fd82a036a413ae21702cd1))

#### Fixed

- Early in a meeting, the transcript no longer runs several people's lines into one paragraph ([00c57e3](https://github.com/wquguru/cicada/commit/00c57e34346b0a22a845822534e49144b3fc7e7d))
- Saying yes to a fixed name fixes the rest of the meeting heard the same way at once, not only with the next line ([46dae9f](https://github.com/wquguru/cicada/commit/46dae9fa7cfc77a703a33d162e7ad54b34b96852))
- In English, Japanese and Korean, a to-do's owner no longer shows as 对方, 你 or 说话人2 ([5d20f2e](https://github.com/wquguru/cicada/commit/5d20f2e1a7617ebe680be59c31a0679c3839ecbf))
- Edit line… no longer teaches the word list punctuation or words added around the heard ones ([28ab28e](https://github.com/wquguru/cicada/commit/28ab28e0f29219a46a55f3074b64821b16fa7882))
- Edit line… that adds a word fixes only that line, never every line with a full stop, and adding a word at the start works ([bc6cc3c](https://github.com/wquguru/cicada/commit/bc6cc3c5b8e3242a447756c09f103f4fc75fafe9))
- The toast after Edit line… shows the span an added word changed (in → in now), not a fragment ([194cdd1](https://github.com/wquguru/cicada/commit/194cdd16d7530f771f60aca7d663017d3efe2642))
- Revert and the heard-as chips name an added word whole (in → in now), not "→ now" with nothing before the arrow ([cc718cc](https://github.com/wquguru/cicada/commit/cc718cc16727c1d9d495cc995eb51ba9c719e52a))
- Revert works on a line edited, reverted and edited the same way again, and dropping a word names both sides of the change ([3dc4aa1](https://github.com/wquguru/cicada/commit/3dc4aa11bb015e618603737b4374811725420207))

### Windows

#### New

- Misheard names and terms are fixed in subtitles and live notes as the meeting goes ([40c173d](https://github.com/wquguru/cicada/commit/40c173dca1012f8cc732c5210d9698d8c703a284))
- Fix a misheard word in the transcript or the meeting record, answer new names in the notes window, and keep a word list in Settings ([b3e4805](https://github.com/wquguru/cicada/commit/b3e48051dd93cb6fc0a3b5a4c75bfd3ee8e3f5b4))

#### Fixed

- A meeting record whose misheard words were fixed on the Mac shows the fixed words on Windows and keeps the fixes when saved ([e588aa0](https://github.com/wquguru/cicada/commit/e588aa0a33f4a58ccbdde6444f7693662b98ed95))
- Saying yes to a fixed name fixes the rest of the meeting heard the same way at once, not only with the next line ([e38bd1b](https://github.com/wquguru/cicada/commit/e38bd1be856c92610f6475861c0624e311bc52d6))
- In English, Japanese and Korean, a to-do's owner no longer shows as 对方, 你 or 说话人2 ([d5fbff2](https://github.com/wquguru/cicada/commit/d5fbff2957f11833eb2e60aedd013cf1c2e4979d))
- Edit line… no longer teaches the word list punctuation or words added around the heard ones ([331e094](https://github.com/wquguru/cicada/commit/331e094a6ded82ca32ba5cc152659e2c8fb279df))
- Edit line… that adds a word fixes only that line, never every line with a full stop, and adding a word at the start works ([53846ad](https://github.com/wquguru/cicada/commit/53846adf3d0f08a1a705be768557cebd34aa0bd3))
- Revert and the heard-as chips name an added word whole (in → in now), not "→ now" with nothing before the arrow ([183f049](https://github.com/wquguru/cicada/commit/183f0491c9aafe5e6e43510349d24267fa0b5502))
- Revert works on a line edited, reverted and edited the same way again, and dropping a word names both sides of the change ([e3dd6b8](https://github.com/wquguru/cicada/commit/e3dd6b886ae26283622a6868da6670ac1ce613f0))

### Android

#### New

- Misheard names and terms are fixed in subtitles and live notes as the meeting goes, with new names asked about once ([6f9a9ff](https://github.com/wquguru/cicada/commit/6f9a9ff88251b22c0a74b45055082865c0bee944))
- Fix a misheard word yourself from the meeting record, confirm new names live, and keep your spellings in Settings › Word list ([815a2bf](https://github.com/wquguru/cicada/commit/815a2bfa95258caa913180d2260d54ed425483e5))

#### Fixed

- Meeting records from the Mac keep their fixed words, and show, search and export the fixed text ([481ef8d](https://github.com/wquguru/cicada/commit/481ef8d0900ad6f1556a0a86a8c4dd6c3f671a93))
- Saying yes to a new name fixes the rest of the meeting heard the same way at once, not only with the next line ([f2e6945](https://github.com/wquguru/cicada/commit/f2e6945e8c90ced76802a133b7816334fa68e26d))
- The Word list says Tap to change the spelling, not Click, in English, Japanese and Korean ([0e5c8b2](https://github.com/wquguru/cicada/commit/0e5c8b2fe5d231c18295a65fb04919b2fafcc18b))
- In English, Japanese and Korean, a to-do's owner no longer shows as 对方, 你 or 说话人2 ([ea9dd62](https://github.com/wquguru/cicada/commit/ea9dd622de5a5ad8c3f25718399de6b520584912))
- Edit line… no longer teaches the word list punctuation or words added around the heard ones ([7a11c5a](https://github.com/wquguru/cicada/commit/7a11c5a4023f64d709fa7f622ddd24dfa22426db))
- Edit line… that adds a word fixes only that line, never every line with a full stop, and adding a word at the start works ([2f51cd8](https://github.com/wquguru/cicada/commit/2f51cd877171023b3ca7ab6a7969d5d55249e0cb))
- The toast after Edit line… shows the span an added word changed (in → in now), not a fragment ([b842de4](https://github.com/wquguru/cicada/commit/b842de461a5aec59ad31cfc77c2019c10e099190))
- Revert and the heard-as chips name an added word whole (in → in now), not "→ now" with nothing before the arrow ([f215e24](https://github.com/wquguru/cicada/commit/f215e24e15d55bc86762fd7b5b7fa1cd6b03a9da))
- Revert works on a line edited, reverted and edited the same way again, and dropping a word names both sides of the change ([20244ea](https://github.com/wquguru/cicada/commit/20244ea6b7a9af46a596224c4da0f183cac76a33))

### Linux

#### New

- Meeting records keep the words fixed on the Mac and show them fixed ([1f37aac](https://github.com/wquguru/cicada/commit/1f37aac7645502421c50718d8df1fb6cff0a1a0d))
- Misheard names and terms are fixed in subtitles and live notes as the meeting goes, with new names asked about once ([b179ff0](https://github.com/wquguru/cicada/commit/b179ff0c3cf54f1154d80f4eb4f7ed6ebe952e08))
- Fixed words are underlined, the notes window asks Is this fix right? without taking focus, Edit line… works in the meeting record, and Settings has a Word list ([aa1563a](https://github.com/wquguru/cicada/commit/aa1563a3a572a5061e7654b6cfea1441293ea75a))

#### Fixed

- The live notes window can be dragged again ([29e353b](https://github.com/wquguru/cicada/commit/29e353bce76bd71d8eeb3385e5bce1af6cf52cad))
- Saying yes to a fixed name fixes the rest of the meeting heard the same way at once, not only with the next line ([bd14ca1](https://github.com/wquguru/cicada/commit/bd14ca118a7b47f69578fa0445d7bb8702dd912a))
- In English, Japanese and Korean, a to-do's owner no longer shows as 对方, 你 or 说话人2 ([75164ec](https://github.com/wquguru/cicada/commit/75164ec08881cfeb038e0bc4206464dae02de15e))
- Edit line… no longer teaches the word list punctuation or words added around the heard ones ([ab28ff7](https://github.com/wquguru/cicada/commit/ab28ff7286535d171e18f61950913c287e300cf5))
- Edit line… that adds a word fixes only that line, never every line with a full stop, and adding a word at the start works ([bd62bda](https://github.com/wquguru/cicada/commit/bd62bda660ff127a1acf273242cfd60f2659cfb3))
- The toast after Edit line… shows the span an added word changed (in → in now), not a fragment ([4f3f75a](https://github.com/wquguru/cicada/commit/4f3f75a862f1e0ff62956a31d8c0c3bb8cd86978))
- Revert and the heard-as chips name an added word whole (in → in now), not "→ now" with nothing before the arrow ([db02021](https://github.com/wquguru/cicada/commit/db02021f94f7f7303ec2c845860a3fa60852cea4))
- Revert works on a line edited, reverted and edited the same way again, and dropping a word names both sides of the change ([6e5c5cb](https://github.com/wquguru/cicada/commit/6e5c5cb192b212121edebf68e643825b9b3d29d0))

## 1.5.0 — 2026-11-07

### Mac

#### New

- What you say with the talk key is marked Interpreted in subtitles, records and exports, and goes only to people online, never the speakers ([3d0a438](https://github.com/wquguru/cicada/commit/3d0a438c6e1b5205b106fb2ac963bc9605d87845))

#### Fixed

- With the meeting turned down low, Cicada no longer says it can't tell the language while people are talking ([9dbb4e8](https://github.com/wquguru/cicada/commit/9dbb4e804b23bc58decb55f3d8764948c53f8dd7))
- Holding the talk key without a virtual mic says so in the subtitle bar or notes window instead of doing nothing ([f9371fc](https://github.com/wquguru/cicada/commit/f9371fcafddb816dc927190685da918e108ce65d))
- With OpenRouter's default model, notes no longer fail when the host it picks refuses JSON mode ([d60a59f](https://github.com/wquguru/cicada/commit/d60a59f6f420e937f860b623e346b37744181d02))
- In Japanese, the interpreted tag on your lines says 自分 everywhere, as the rest of the app does ([9269c24](https://github.com/wquguru/cicada/commit/9269c249ddd8f477e4a096136a683fc8284d7585))
- Speaker names from your AI service are still found when the reply comes wrapped in a code block ([b9aa1d0](https://github.com/wquguru/cicada/commit/b9aa1d0f37da5054a63bd18dc76439a0a164073f))
- In English, a speaker who said one line shows 1 line, not 1 lines ([a99fb7f](https://github.com/wquguru/cicada/commit/a99fb7f6a26b77cf57759afdb059002e90dd82db))
- In English, the remaining counts of one say 1 line and 1 person, not 1 lines and 1 people ([4078e07](https://github.com/wquguru/cicada/commit/4078e0799f25d438570de2b5b9270da4a7e9026d))

### Windows

#### New

- What you say with the talk key is marked Interpreted in the notes, records and export ([d2033ea](https://github.com/wquguru/cicada/commit/d2033ea91f4510d69bb55baf4f3ceb2d083062a0))
- The bar shown while you hold the talk key is marked Interpreted too, as in the notes and records ([0eac772](https://github.com/wquguru/cicada/commit/0eac772bab10c14cee635cf73a6c91ca58828f79))

#### Fixed

- If VB-Cable goes away while you hold the talk key, Cicada says nothing was sent instead of Sent to meeting, and keeps the line out of the record ([8cabc92](https://github.com/wquguru/cicada/commit/8cabc92ebbe4d6248d9f747813b156426a7a8f9c))
- After a long sentence with the talk key, the bar's Speaking to others / Sent to meeting status is no longer pushed off its edge ([ef7839f](https://github.com/wquguru/cicada/commit/ef7839f17bd72c8ff7d288631e373628d3639cd9))
- After onboarding's sound check, the interpreting step no longer says VB-Cable isn't installed when it is ([47895a5](https://github.com/wquguru/cicada/commit/47895a5e4fa250f2d45cb1ded1422b0ee0ebfade))
- With OpenRouter's voice, the talk key no longer gets stuck on Speaking to others after the first sentence ([f598b84](https://github.com/wquguru/cicada/commit/f598b84997a7e3ae4a2ddf9a2b47339921e36b2e))
- With OpenRouter's default model, notes no longer fail when the host it picks refuses JSON mode ([b756cd8](https://github.com/wquguru/cicada/commit/b756cd8e9d4461008a9fa02ed22eccfe06f1ed52))
- In English, a meeting with one line says 1 line, not 1 lines ([7250b1e](https://github.com/wquguru/cicada/commit/7250b1e674094b0abaa75623076dc93eb65cdf07))
- On a small screen, the talk bar no longer covers the notes panel's live line ([82e8138](https://github.com/wquguru/cicada/commit/82e8138e68959a4e11c49bf4bd8b35ffc036807f))

### Android

#### New

- What you say with Me speaking is marked Interpreted in Face to face, live subtitles, records and exports ([af66480](https://github.com/wquguru/cicada/commit/af66480fe6b69ca471318ce5132aac4912b9673a))

#### Fixed

- The themed icon in dark mode no longer shows the cicada's eyes inverted ([cde3852](https://github.com/wquguru/cicada/commit/cde3852bcd38756bbd715d022be90a742fa4333e))
- The floating subtitle bar marks what you say with Me speaking as Interpreted ([e24b199](https://github.com/wquguru/cicada/commit/e24b1990cedd3857ec5d058861fd36cef99cb495))
- After changing the app language mid-meeting, the End button follows it ([3133f9a](https://github.com/wquguru/cicada/commit/3133f9a06137849b980f305cc4f16342df9aed00))
- With OpenRouter's default model, notes no longer fail when the host it picks refuses JSON mode ([81caf15](https://github.com/wquguru/cicada/commit/81caf15e491db3a83167bfd10a7d4bb188518f3c))
- In English, a meeting with one line says 1 line, not 1 lines ([fefcc60](https://github.com/wquguru/cicada/commit/fefcc60377dd19c40e222983f7838d6a246d7154))

### Linux

#### New

- What you say with interpreting on is marked Interpreted in the notes, records and export ([d3d9458](https://github.com/wquguru/cicada/commit/d3d94589c21dfd668ca7770d99f2756af055057c))

#### Fixed

- Setup, settings and the meetings window say people online hear your interpreted voice, not "them" or the room ([a81c939](https://github.com/wquguru/cicada/commit/a81c939d140c78f8e4c272200d92c575e55281da))
- With OpenRouter's default model, notes no longer fail when the host it picks refuses JSON mode ([4483f0e](https://github.com/wquguru/cicada/commit/4483f0e1745d02c1953b8bf767e97e122735d65c))
- In English, a meeting with one line says 1 line, not 1 lines ([be9fa79](https://github.com/wquguru/cicada/commit/be9fa796a41d7a3a5669be6bf95279501627499b))
- A new meeting's notes window no longer keeps showing the last meeting's interpreted sentence ([ddc29ef](https://github.com/wquguru/cicada/commit/ddc29efb3b48b1845a4b37b61cfc2b7d3bde0538))

## 1.4.0 — 2026-11-06

### Mac

#### New

- When an AI service has trouble, the notes window says in one line what is waiting and what still works, with Use Ling one click away ([1e59953](https://github.com/wquguru/cicada/commit/1e59953cef2c1c9aa049f80b5ccb3d8acfe66c53))
- A Turn on mic button in the menu bar panel, Live notes and the subtitle bar replaces Listen to, and people at the table are heard over music and with headphones on ([fc7e395](https://github.com/wquguru/cicada/commit/fc7e3954c33b28fe90746c1fc404241dff9dda57))
- A meeting's recording plays back in its record, a click on a line's time plays from there, and the line playing lights up and stays in view ([acee2d2](https://github.com/wquguru/cicada/commit/acee2d2517250b7cf335a9a7eb020a5cc554634c))
- With your own AI service, meeting audio and text can stay off Google Translate ([d019283](https://github.com/wquguru/cicada/commit/d019283f9bba4887bc48d5aae6246256c853805f))
- The meeting transcript is re-heard on the Mac and comes out with far fewer misheard words ([44dbce6](https://github.com/wquguru/cicada/commit/44dbce6df5d4acde9aebcf7659bf71b41c426b14))

#### Fixed

- Switching AI service right after a meeting no longer shows the new one as connected because the old one answered the meeting's last notes ([c4b12b6](https://github.com/wquguru/cicada/commit/c4b12b63307848bc3487abc4391ad1e9307ec2e2))
- Holding the talk key no longer quits Cicada when the microphone's format differs from the system input ([1bdce0a](https://github.com/wquguru/cicada/commit/1bdce0a2a0ffdc62261be35262fb80424f958432))
- Generate Notes on a long meeting no longer drops a topic and keeps only its "(continued)" end ([452aaec](https://github.com/wquguru/cicada/commit/452aaec5c6091f61358953583c15e03c5614460b))
- When the AI service hearing an Intel Mac's meeting keeps answering with a server error, the status says it is having trouble instead of that it can't be reached ([59d161b](https://github.com/wquguru/cicada/commit/59d161b6aec19bb2ea393822c6c690f61cb88c48))
- The local network prompt says Cicada only uses it to reach the AI server you set up on your local network ([35e6370](https://github.com/wquguru/cicada/commit/35e6370d685e9f568663b8ab995b21eb565a0fa5))
- When Cicada isn't allowed on the local network, AI Service says so and opens the right System Settings pane instead of showing a dead server ([13fb423](https://github.com/wquguru/cicada/commit/13fb423d5f860f0cd4c3b4404c945965e8615e80))
- A cause in a meeting's fishbone diagram is timed by the lines it cites, not a time past the meeting's end ([316b9ca](https://github.com/wquguru/cicada/commit/316b9cace5a3ef67da29cb120727867f421be48e))
- When Ling hears the meeting and is briefly too busy, it tries again for about 15 s instead of losing the line ([70df016](https://github.com/wquguru/cicada/commit/70df016a25ab37947926d6c09a5b41ec75c267a7))
- The Rewrite in English button after a meeting has spaces around English in Chinese ([5223610](https://github.com/wquguru/cicada/commit/52236102430c7dbcd8f21d90ea0c7e1aa4e36b2b))
- Subtitles no longer stall when Google Translate can't be reached, and without a key the notes window says what to do ([b8d0e47](https://github.com/wquguru/cicada/commit/b8d0e47ecc098aace64c969f40ee89ef2e13bb00))
- When your own AI service can't be reached, subtitles no longer wait a few seconds on every line before Google translates them ([89485cb](https://github.com/wquguru/cicada/commit/89485cb90332fe30cd58a8deb51138d03c34b0f9))
- The room mic no longer goes silent when the system input is a virtual mic with a different format ([813bc64](https://github.com/wquguru/cicada/commit/813bc64fce002cf6ca8002c4ff95ffb8a4167b8e))
- Recording a voice sample no longer crashes when the system input is a virtual mic with a different format ([257c9ce](https://github.com/wquguru/cicada/commit/257c9cea72d361d1403d9f25e3a4bd170f18ddc7))
- After a meeting on headphones, the next meeting on speakers no longer lets the first online sentence into the room's lines ([4f72d4b](https://github.com/wquguru/cicada/commit/4f72d4b2ab29e21fa4192d648a6f7a6533452b77))
- Holding the talk key with AirPods as the microphone no longer quits Cicada ([5e0a421](https://github.com/wquguru/cicada/commit/5e0a421f799c0d9e7b3c8c54ee04d217f3603d50))
- Holding the talk key without saying anything no longer sends "Hmm." into the meeting ([88ac648](https://github.com/wquguru/cicada/commit/88ac6489acbed633b1a06691bd6b78b3073071bb))
- With the meeting on the speakers, the talk key no longer sends the other side's own words back into the meeting ([5e2e955](https://github.com/wquguru/cicada/commit/5e2e955b7e7708efbf097be7d77fe6c33a7d7f0d))
- A meeting in Lark (international) counts as a call ([1bf9a71](https://github.com/wquguru/cicada/commit/1bf9a71267ba48c6943a9649fdf86a31fd3b6c5e))
- A meeting in WeCom or Webex Meetings counts as a call ([4b93ac1](https://github.com/wquguru/cicada/commit/4b93ac1e40f70163c8933057a66694e60bfb8647))
- Subtitles keep coming when the output device runs at 16 kHz, as a headset in a call does ([1644770](https://github.com/wquguru/cicada/commit/1644770b93ce8a15bc0b02916673054bb38d6b06))
- With the mic on, a table speaking mostly short sentences is no longer left out of the whole meeting ([b7b28ca](https://github.com/wquguru/cicada/commit/b7b28caf063c1b986b59910b92a428d238998cff))
- With the mic on, holding the talk key no longer garbles what you say or keeps your voice from reaching the meeting ([fa1677e](https://github.com/wquguru/cicada/commit/fa1677edfca6a8122edf59f1bed7fc8ff3bf294a))
- With the mic on and the meeting on the speakers, the talk key no longer sends the other side's own words back into the meeting ([e41a689](https://github.com/wquguru/cicada/commit/e41a6890c3573978c863e1de154c3f4fd0db94bd))

### Windows

#### New

- When an AI service has trouble, the notes window says in one line what is waiting and what still works, with Use Ling one click away ([9f31a53](https://github.com/wquguru/cicada/commit/9f31a5385caa56127b24c9d5ae8dc96586d7744c))
- A Turn on mic button in the tray panel, Live notes, the subtitle bar and the tray menu replaces Listen to, and people at the table are heard over music and with headphones on ([a5212cc](https://github.com/wquguru/cicada/commit/a5212cc96e54a1a80b73773d819772eba2b9e774))
- Meetings are recorded, and the recording plays back in the record, a click on a line's time plays from there, and the line playing lights up ([0f98e96](https://github.com/wquguru/cicada/commit/0f98e968ba4411cadefcc7060628b83e13026109))
- With your own AI service, meeting audio and text can stay off Google Translate ([6e90cdf](https://github.com/wquguru/cicada/commit/6e90cdf00ad943434b89a7af7300198c2a798d9a))

#### Fixed

- Generate Notes on a long meeting no longer drops a topic and keeps only its "(continued)" end ([51c99ac](https://github.com/wquguru/cicada/commit/51c99ac26c6ed6cde69b7c107925166247579420))
- A quiet short phrase on its own, like a soft "Good morning everyone" opening a meeting, is no longer dropped ([a9849e2](https://github.com/wquguru/cicada/commit/a9849e295e219bb1fc93739db663975d07126c70))
- When the AI service keeps answering a meeting's audio with a server error, the notes window says so instead of leaving the subtitles silently empty or blaming the network ([dbe59ed](https://github.com/wquguru/cicada/commit/dbe59edc5eda1d893828752749bb74204ef5fa3d))
- A cause in a meeting's fishbone diagram is timed by the lines it cites, not a time past the meeting's end ([dd76ede](https://github.com/wquguru/cicada/commit/dd76ede31d1ce4c884336a5197625da84fded412))
- A quiet short phrase on its own is kept however its first moments line up with the audio, and a faded-in hiss no longer passes as a word ([1d193be](https://github.com/wquguru/cicada/commit/1d193be72249b8312204f780bbf83b8a1d813bf1))
- When your own AI service can't be reached, subtitles no longer wait a few seconds on every joined sentence before Google translates it ([f61c0f1](https://github.com/wquguru/cicada/commit/f61c0f171378a80ee89b3410f99cb84038963240))
- The custom voice model and voice fields show their hint in English, Japanese and Korean again ([693f407](https://github.com/wquguru/cicada/commit/693f4079532995f60f14f814a9633a258cd7fd12))
- The talk key no longer sends "Hmm." for a press nobody spoke in, or the other side's own words back while the meeting plays ([dbd92d8](https://github.com/wquguru/cicada/commit/dbd92d845b5daba47dd86e9f96ba1a1b44831642))
- A meeting in WeCom counts as a call ([8a58820](https://github.com/wquguru/cicada/commit/8a588201a4c4c85b33041fd6e61d201d0a0dcb62))
- The tray panel's microphone row and the no-microphone notice say PC instead of Mac in English, Japanese and Korean ([0c214db](https://github.com/wquguru/cicada/commit/0c214db298233c0489bf59305a742674bce52868))
- The tray panel's Hide notes button is no longer cut off in English and Japanese ([6767b0e](https://github.com/wquguru/cicada/commit/6767b0e06cb21fe7fff78be8874b60416b2119f4))
- The notes window's collapse button stays in view in English while listening, next to Turn on mic and End ([ac3d713](https://github.com/wquguru/cicada/commit/ac3d713b53eebc1856e3c6428b7aababdbcff56e))
- With your own AI service, the notes window's line about waiting for it names its address instead of Other (OpenAI-compatible) ([7f5c19e](https://github.com/wquguru/cicada/commit/7f5c19e34b3d149cfb6d7565ead05fda19b4f619))
- The tray panel's Hide notes button is no longer cut off in Korean ([b650fc2](https://github.com/wquguru/cicada/commit/b650fc293275ec31d25fdd454e7f8e9ed38b1889))
- Quitting right after ending a meeting keeps its last sentences instead of leaving an empty record ([e49db5c](https://github.com/wquguru/cicada/commit/e49db5c2186db16dca97c3aa92620cd973c25763))

### Android

#### New

- When an AI service has trouble, the live screens say in one line what is waiting and what still works, with Use Ling one tap away ([65d93f5](https://github.com/wquguru/cicada/commit/65d93f5bb78d527af735c62e2116caebba9425b8))
- A meeting's recording plays back from a bar at the bottom of its record, a tap on a line's time plays from there, and the line playing lights up ([304d5ed](https://github.com/wquguru/cicada/commit/304d5ed1c2af61c3cb66ea4e2147a269da0b90f3))
- With your own AI service, meeting audio and text can stay off Google Translate ([3b33793](https://github.com/wquguru/cicada/commit/3b337934aa7ddd3edb473159e09c8b2fd5e5f9a4))
- Android tells the other side's voices apart and names them, with the Mac's voiceprint model ([3167539](https://github.com/wquguru/cicada/commit/31675397078ab7bffb86d0400d7490bf22726afc))

#### Fixed

- Generate Notes on a long meeting no longer drops a topic and keeps only its "(continued)" end ([6c33dad](https://github.com/wquguru/cicada/commit/6c33dad4cf979cce67e11fb47e8e261a2ccafdc2))
- A quiet short phrase on its own, like a soft "Good morning everyone" opening a meeting, is no longer dropped ([8c329da](https://github.com/wquguru/cicada/commit/8c329dac8d09e9149c10004e8f8b5c9973198503))
- When the AI service keeps answering a meeting's audio with a server error, the banner says so instead of leaving the subtitles silently empty ([34b0199](https://github.com/wquguru/cicada/commit/34b0199c33db84bd06eb6f1be9867e00033afd95))
- A cause in a meeting's fishbone diagram is timed by the lines it cites, not a time past the meeting's end ([354c011](https://github.com/wquguru/cicada/commit/354c01169293cfe3dbd9177b68f49fb8f9d78f25))
- Right after a meeting, AI Service says the service was used in a meeting just now instead of now ([6f4f85d](https://github.com/wquguru/cicada/commit/6f4f85d1bad1d7b3635c04daeec6fa65914d07eb))
- A quiet short phrase on its own is kept however its first moments line up with the audio, and a faded-in hiss no longer passes as a word ([c4e3a44](https://github.com/wquguru/cicada/commit/c4e3a44eb5f506efdee900897f00420225b871ce))
- When your AI service can't be reached, lines it would translate go straight to Google instead of waiting seconds for it each time ([7ad8fd5](https://github.com/wquguru/cicada/commit/7ad8fd53e3ed53ee5e5c099b37210273e55c32c5))
- The custom voice model and voice fields show their hint in English, Japanese and Korean again ([8b1be24](https://github.com/wquguru/cicada/commit/8b1be2436c835a55cf9a6776915c123f671e91ec))
- Holding the talk button without saying anything no longer says "Hmm." to the other person ([828a254](https://github.com/wquguru/cicada/commit/828a2549899e0f56d9d13931da6d98b260673277))

### Linux

#### New

- When an AI service has trouble, the notes window says in one line what is waiting and what still works, with Use Ling one click away ([3128d5b](https://github.com/wquguru/cicada/commit/3128d5ba4fb2b8986e329de7456e257c5b96949a))
- A Turn on mic button in Live notes and the top-bar menu replaces Listen to, and people at the table are heard over music and with headphones on ([d950c74](https://github.com/wquguru/cicada/commit/d950c74695e4a17d040a07794f21056a839adf6d))
- With third-party media formats installed, meetings are recorded and play back in the record, a click on a line's time plays from there ([9492626](https://github.com/wquguru/cicada/commit/9492626f044aee06683b5d3b7facc321c0a411d0))
- With your own AI service, meeting audio and text can stay off Google Translate ([31aee74](https://github.com/wquguru/cicada/commit/31aee74c6213b0d8d566866dd2f7a9f721be9ffb))

#### Fixed

- Generate Notes on a long meeting no longer drops a topic and keeps only its "(continued)" end ([c3493fc](https://github.com/wquguru/cicada/commit/c3493fc26701eb52e2d399d4626f621e8d9ed994))
- A quiet short phrase on its own, like a soft "Good morning everyone" opening a meeting, is no longer dropped ([2567d1b](https://github.com/wquguru/cicada/commit/2567d1b5ef3c126eb1154f6512a9287081b31d39))
- When the AI service keeps answering a meeting's audio with a server error, the notes window says so instead of leaving the subtitles silently empty ([38464e2](https://github.com/wquguru/cicada/commit/38464e26fb2048871ce9bd40614c46f2334905b6))
- A server error before the first line shows in full on the waiting card instead of being cut off ([fb84d0c](https://github.com/wquguru/cicada/commit/fb84d0cc9aacb28dd926c255821798cd961fda40))
- In English, a server error from your own AI server names it Other (OpenAI-compatible) instead of in Chinese ([e9618cd](https://github.com/wquguru/cicada/commit/e9618cd95861fd4eabdf644337afeebd4a176d00))
- A cause in a meeting's fishbone diagram is timed by the lines it cites, not a time past the meeting's end ([0c382a2](https://github.com/wquguru/cicada/commit/0c382a23044d82bb7b8245ff4e192888bccf16db))
- A quiet short phrase on its own is kept however its first moments line up with the audio, and a faded-in hiss no longer passes as a word ([1fa717f](https://github.com/wquguru/cicada/commit/1fa717f62aef98ed89dfda4b6c603c5ffa4df449))
- When a custom AI service's text address can't be reached, translations no longer wait seconds on every line before Google translates them ([be87d6d](https://github.com/wquguru/cicada/commit/be87d6da993eef4649c642051f26754a7c32daae))
- After a meeting on headphones, the next meeting on speakers no longer lets the first online sentence into the room's lines ([c58d0d4](https://github.com/wquguru/cicada/commit/c58d0d44494cd7d6299f2b6df584a136ceb3c95c))
- 同声传译 no longer says "Hmm." when a hush or an echo's tail is heard as only 嗯 ([4de05e2](https://github.com/wquguru/cicada/commit/4de05e2d785fb62fe27a8fa0d3ec1dcff07398a9))
- Third-party media formats installed while Cicada is open turn on Save meeting audio and playback without a restart ([e3566d1](https://github.com/wquguru/cicada/commit/e3566d184bb587bf5d4350eb412820bd753a27ef))
- In English, Japanese and Korean, the notes window's mic row says computer audio only instead of Mac audio only ([1540e35](https://github.com/wquguru/cicada/commit/1540e355b303776fec9a9c981b91dbfb1cc11546))

## 1.3.0 — 2026-11-05

Intel Macs, Listen to › Room on Windows and Linux and Computer + Room on every desktop, your own AI servers per job (including speech recognition on the Mac), alerts when the AI service needs you, and steadier notes in long meetings.

### Mac

#### New

- Clicking Start listening shows the Live notes window right away instead of waiting for someone to speak ([277df6c](https://github.com/wquguru/cicada/commit/277df6ce16903f03cc1324b3fb663eee4e9e3e8e))
- When a speech model is slow to download, the card shows how long it has waited and offers to let Ling listen until it's in ([e288be1](https://github.com/wquguru/cicada/commit/e288be1c4f6dad3ff6a670e84c9775b5d1dc6097))
- Listen to › Mac + Room hears the online meeting and the people at the table together, and records each remote sentence once ([e87615f](https://github.com/wquguru/cicada/commit/e87615fb911d160f7de72c57200fee585538aa92))
- In Mac + Room meetings each line says whether it was heard in the room or online ([afb45f9](https://github.com/wquguru/cicada/commit/afb45f96a04833ac478902fe62ee0ea706a7929e))
- While listening to the Room, Cicada offers to hear the Mac too when a meeting app is in a call ([388d405](https://github.com/wquguru/cicada/commit/388d40504f916b976fae6ebba6baa53a31944981))
- In Mac + Room the panel says when the room pauses for online speech, uses the Mac's mic, or needs the microphone ([6f0da46](https://github.com/wquguru/cicada/commit/6f0da46c93ef3c20e2eddfcb4f4305592c100092))
- Cicada now runs on Intel Macs, with Ling hearing the meeting in place of a speech model ([f6334d0](https://github.com/wquguru/cicada/commit/f6334d063a2689f95be0bb336fd0dcd76608bed1))
- When the room's microphone isn't allowed, the notes window, the subtitle bar and an orange dot on the menu bar icon say so, with one notification if the notes window is put away ([f9ad4fa](https://github.com/wquguru/cicada/commit/f9ad4fa069f3d404320ddfd7666839a3d251a828))
- Speech recognition can go to your own server instead of the Mac, and falls back to the Mac when that server stops answering ([0eea447](https://github.com/wquguru/cicada/commit/0eea4471f2cb20996401cb63cf0e1186cbce6cde))
- Your own AI server can be set per job (translation and notes, speaking voice, recognition), on a LAN or Tailscale address over http with no key, and its check says when the model thinks before answering ([c628a84](https://github.com/wquguru/cicada/commit/c628a841e24ae7a082555bd0dbfec621194cfbfa))
- Scrolling down a meeting record keeps its title and the Notes / Transcript tabs on top, and clicking the title goes back to the start ([37ed6b8](https://github.com/wquguru/cicada/commit/37ed6b8b6e7320959f9146c23c3b8a2c41206e44))

#### Fixed

- Key clicks in the meeting audio no longer count as someone speaking, so pauses and the end of a meeting are noticed on time ([858e763](https://github.com/wquguru/cicada/commit/858e7632da33ad6143ee991a0addda6bed7a7489))
- While Ling listens in place of a speech model, hold music, ringtones and alerts are no longer sent to it ([e31f122](https://github.com/wquguru/cicada/commit/e31f1223bed8c88ca0d1be274f2158d14088ac87))
- A renamed meeting title is saved when you click away or pick another meeting, and shows a pencil on hover ([54388e9](https://github.com/wquguru/cicada/commit/54388e9dd0a6f534850d044f454ef5519b9fb5d3))
- When the room's microphone is unplugged, Cicada moves to another one and says so, or hears the Mac alone ([e4cb18f](https://github.com/wquguru/cicada/commit/e4cb18f8e9471bc54413b8c3181b69ee9d448f19))
- In a meeting switched from Mac + Room to Room, later room lines are no longer marked Online ([3443308](https://github.com/wquguru/cicada/commit/344330885ebe64a216d4b0a3c35779b7348188e3))
- The AI service menu reads "Ling (Recommended)" in English and Korean, with a space before the bracket ([c4d973a](https://github.com/wquguru/cicada/commit/c4d973af58542a40f815afeff230cf8aa9762940))
- The live notes window no longer covers the welcome guide's buttons on small screens ([4acfab7](https://github.com/wquguru/cicada/commit/4acfab7e5c8684490d5ad6aa4ac29d9266a0628b))
- The room is heard in your own language from the start, and room lines show even when its language isn't certain ([03f67ac](https://github.com/wquguru/cicada/commit/03f67ac4bdfb08ec0c9aa09a24fa65cbf5e4180c))
- Live notes keep the listening animation until the first notes are actually being written ([599614a](https://github.com/wquguru/cicada/commit/599614a36112bd1de3ffde79dd3b3ed18118ecbf))
- Live notes keep updating through hours-long meetings without one topic swallowing the rest, and a long meeting's full notes cover all of it ([1c15482](https://github.com/wquguru/cicada/commit/1c15482c783948922d784922301cd53921d67792))
- The notes window no longer says notes stopped at 00:00 when only another request lost the network ([a99c380](https://github.com/wquguru/cicada/commit/a99c380d17f7860ae42713ab2c3c040d604933a5))
- A meeting whose language took over a minute and a half to settle still tells its speakers apart ([04da0bd](https://github.com/wquguru/cicada/commit/04da0bd2427d63bcd06839d8a8715161cda0b852))
- A new meeting's notes window no longer shows the last meeting's subtitle until someone speaks ([9826d46](https://github.com/wquguru/cicada/commit/9826d461d8034315e54ae2345859f1ed984e0b8d))
- Changing a custom AI service's settings while it is being checked no longer flashes it as unreachable ([f92a291](https://github.com/wquguru/cicada/commit/f92a2912f8d743cd93afbf2c21f1e90597579927))
- Switching speech recognition back to this Mac, or to another AI service, during a meeting stops sending its audio to the service ([a2746a2](https://github.com/wquguru/cicada/commit/a2746a283f2c6116b8cec6c6bf99826476268e6e))
- Translations heard by the AI service no longer start with a note about which language the meeting is in ([7c0be87](https://github.com/wquguru/cicada/commit/7c0be8720cd11f946a31d9da9e2469c06015bcc5))
- A long meeting's live notes no longer give a topic a start time minutes after what was said in it ([e6ccaac](https://github.com/wquguru/cicada/commit/e6ccaacc266420d5d7062959331fb61bddf2410b))
- A server on the local network that can't be reached no longer gets advice to turn on a proxy ([73c0457](https://github.com/wquguru/cicada/commit/73c04579518e954a9f11690f217a6b6f874848f4))

### Windows

#### New

- Listen to › Room hears the people at the table through a microphone ([85e1cbf](https://github.com/wquguru/cicada/commit/85e1cbf63747c28c57ab0ae1d048a3bd608b6a95))
- Listen to › PC + Room hears people online and at the table together, each line marked In room or Online ([b566fff](https://github.com/wquguru/cicada/commit/b566fff397f654ff2c48ceb76e1bf283c9372d3e))
- When the AI service needs you to fix something, like a key that stopped working, the tray icon shows an orange dot naming it, and one notification per meeting if the notes window is put away ([fd1550d](https://github.com/wquguru/cicada/commit/fd1550dffe4520b4dfa7661c93a8364c042657b7))
- Your own AI server can be set per job, on a LAN or Tailscale address over http with no key, and its check says when the model thinks before answering ([82c5b38](https://github.com/wquguru/cicada/commit/82c5b38197ec459f9e8f84f6b71e91f425e75568))
- Scrolling down a meeting record keeps its title and the Notes / Transcript tabs on top, and clicking the title goes back to the start ([d9e5bcd](https://github.com/wquguru/cicada/commit/d9e5bcdc8606db602b40a7a441dc27073cc4941e))

#### Fixed

- A Mac + Room record opened on Windows keeps which lines were heard in the room ([4da0a22](https://github.com/wquguru/cicada/commit/4da0a221a930d173735237e9c1aeb882d26f5fc3))
- In a meeting switched from PC + Room to Room, later room lines are no longer marked Online ([cdd311e](https://github.com/wquguru/cicada/commit/cdd311e3b05265d4bbc1a87eab239558c03f807c))
- A very quiet voice in a meeting is no longer mistaken for a fan or hum and left without subtitles ([0a454cb](https://github.com/wquguru/cicada/commit/0a454cb770634d774c57284e4e3d59a6726704f1))
- A busy moment at Ling no longer loses meeting lines ([612627d](https://github.com/wquguru/cicada/commit/612627d780cffebab786aee1d777c4ee20f8ad07))
- The in-app update no longer gives up after 20 seconds: it keeps going while data arrives and logs why when it stops ([e98a045](https://github.com/wquguru/cicada/commit/e98a0457427c40a786806637dce869a6b9b8967a))
- When an update can't install itself, the tray and settings only say the download page opened if it did ([436d917](https://github.com/wquguru/cicada/commit/436d9175a9f9c90db11b198edc7c6d7b5c68e759))
- Settings › AI Service keeps one width whether the check is running, failed or passed ([67f9c32](https://github.com/wquguru/cicada/commit/67f9c320c00674b1eeca243f2093bfbeca8d596b))
- Turning the system proxy on or off makes Cicada check the AI service again when it couldn't reach it ([123026b](https://github.com/wquguru/cicada/commit/123026bfbd1c8304213dc128f40b474421c10619))
- Starting to listen while the AI service is unreachable asks within about 2 seconds, and Check Again and Start shows Checking… while it looks ([dccfa21](https://github.com/wquguru/cicada/commit/dccfa215b809ca913d97c70a0997d8e73583f3c0))
- A short word on its own, like "Thanks." or a quiet "Good morning everyone" is no longer dropped ([93e74bc](https://github.com/wquguru/cicada/commit/93e74bc95a02370e12fd8ae3cdc2678b79b07b2a))
- A sentence is no longer split in two when the PC or VM delivers its audio a moment late ([ecdc376](https://github.com/wquguru/cicada/commit/ecdc376a84549c9b67f67beb470cd4d00a2e5d8f))
- Low rumble such as brown noise no longer turns into made-up meeting sentences ([cb2c5ca](https://github.com/wquguru/cicada/commit/cb2c5ca687b6681643bbc0da1989644b15a9767e))
- Turning the system proxy off while Cicada is checking the AI service still makes it check again once that check ends ([331831a](https://github.com/wquguru/cicada/commit/331831ac9f5de8d6916ad45d1d8422045f3237ea))
- While no notes are out yet, the notes window shows the listening placeholder and how many lines it heard ([d76a0c8](https://github.com/wquguru/cicada/commit/d76a0c87e461886503219a00b1956b72c5e8c6bf))
- Small icon buttons such as Switch to subtitle bar and the notes window's collapse no longer have their right edge cut off ([3219610](https://github.com/wquguru/cicada/commit/32196103b19e9f2747c74fc98beac09328075724))
- Live notes keep updating through hours-long meetings without one topic swallowing the rest, and a long meeting's full notes cover all of it ([da326fe](https://github.com/wquguru/cicada/commit/da326febd6fe1a26d552f36813fe30465cf26eda))
- The notes window no longer says notes stopped at 00:00 when only another request lost the network ([053f335](https://github.com/wquguru/cicada/commit/053f335b13b721fab08352dd24b8ca287209c2d4))
- Someone typing during a pause no longer joins the sentences either side into one ([bd8efcf](https://github.com/wquguru/cicada/commit/bd8efcf6a56372c11084036297453b7e173d0dd9))
- Translations heard by the AI service no longer start with a note about which language the meeting is in ([a480914](https://github.com/wquguru/cicada/commit/a48091405ede709d14c8887fba9d24b0559ac91c))
- Typing an http address on the internet for your own AI server now says right away that it needs https ([d049dd0](https://github.com/wquguru/cicada/commit/d049dd06abca1a106b6aa4977202d5ea12287c2c))
- The key field of your own AI server shows its whole hint in English, Japanese and Korean, and says PC instead of Mac ([827be47](https://github.com/wquguru/cicada/commit/827be47b7645a2f8494104add9bc55f6a91741a7))
- A long meeting's live notes no longer give a topic a start time minutes after what was said in it ([0ea6180](https://github.com/wquguru/cicada/commit/0ea618084dd63070b66a5a91621a50aa7bf2bac7))
- The update download shows its progress as 39% instead of 39%% ([dedc2dc](https://github.com/wquguru/cicada/commit/dedc2dc05cfa069e9c253700a03db488db7bc156))
- Generate Notes on a meeting record says it is writing them and can't be clicked twice ([1961635](https://github.com/wquguru/cicada/commit/19616354f5c5e761d056ff8210853f4a8bedc8cc))
- A server on the local network that can't be reached no longer gets advice to turn on a proxy ([9bbf2f7](https://github.com/wquguru/cicada/commit/9bbf2f78f0f9963509e8cdf9e587df983e91863d))

### Android

#### New

- In person says that with people online, putting the meeting app on speaker records both sides ([59696d3](https://github.com/wquguru/cicada/commit/59696d3ae9d3de26e278d5baaac453e9ddd96fbf))
- While listening, the notification and the live screen say when the AI key, credit or model needs fixing, with a button that opens AI settings ([93a563f](https://github.com/wquguru/cicada/commit/93a563f2f4537d840984e4e4dbcf87018768ec22))
- Your own AI server can be set per job, on a LAN or Tailscale address over http with no key, and its check says when the model thinks before answering ([31a3e9b](https://github.com/wquguru/cicada/commit/31a3e9b2eacdafc8d9b9868c5c8f154cd01d0af4))
- The app icon is now the same orange cicada as on Mac, Windows and the website ([3222ab9](https://github.com/wquguru/cicada/commit/3222ab94b1476b8b648cf69df156cbd3961f4745))
- Scrolling down a meeting record keeps its title and the Notes / Transcript tabs on top, and clicking the title goes back to the start ([96426c6](https://github.com/wquguru/cicada/commit/96426c60f36fa24801015ca565dac6deef491d6b))

#### Fixed

- A very quiet voice in a meeting is no longer mistaken for a fan or hum and left without subtitles ([e732b4e](https://github.com/wquguru/cicada/commit/e732b4e2a0483a43e283e33fb81084f8598a0aaa))
- A busy moment at Ling no longer loses meeting lines ([a2327ab](https://github.com/wquguru/cicada/commit/a2327ab12dce28e907ac236c5782964fa02afcc9))
- Continue on the intro guide's Ling key step keeps a working saved key when the field is empty ([78e2dd8](https://github.com/wquguru/cicada/commit/78e2dd8662b2482656dc8c7ed3bf0404d1696880))
- Settings and AI Service call face-to-face mode In person, as Home and the listening screen do ([a8ab4ba](https://github.com/wquguru/cicada/commit/a8ab4ba31b604fd706dffef8d85fb55cf5fb6597))
- The Ling key step says where the key is kept in the same words as for every other service ([4fce8fe](https://github.com/wquguru/cicada/commit/4fce8fedd08b442e91ec97e00b4c0836ce9a4058))
- A short word on its own, like "Thanks." or a quiet "Good morning everyone" is no longer dropped ([5c54d7b](https://github.com/wquguru/cicada/commit/5c54d7bd5a44a0a46c28483b9591a1fb8811335b))
- Low rumble such as brown noise no longer turns into made-up meeting sentences ([7e91f43](https://github.com/wquguru/cicada/commit/7e91f43df6a6682161f87bf5987c3642ee66316d))
- While no notes are out yet, the notes page shows the listening placeholder and how many lines it heard ([6b90107](https://github.com/wquguru/cicada/commit/6b9010758de6bf24d527968a44a60031390719f4))
- Live notes keep updating through hours-long meetings without one topic swallowing the rest, and a long meeting's full notes cover all of it ([80dd2c5](https://github.com/wquguru/cicada/commit/80dd2c57c275599803b91b02a8a37b9d19f6f7df))
- When the AI service can't be reached, the listening screen says the subtitles paused too and names a custom service by its address, instead of notes stopped at 00:00 ([b129306](https://github.com/wquguru/cicada/commit/b129306fedbdaf240bb71c3634eca95dc10f449a))
- Someone typing during a pause no longer joins the sentences either side into one ([38334d5](https://github.com/wquguru/cicada/commit/38334d5884465c96f0305f8926cc51a393c7cd34))
- The custom AI service's address and model fields open an English keyboard, so a Chinese keyboard no longer types 192。168 ([82afda5](https://github.com/wquguru/cicada/commit/82afda562c83ed23ea6a7817ad6d202e1bde1f1f))
- Checking a custom AI service says the model thinks first even when the thinking used up its reply, instead of passing it ([cf9e3bb](https://github.com/wquguru/cicada/commit/cf9e3bb324a6389fccb70bb6c278e6f38757f462))
- The listening notification names a custom AI service by its address when it can't be reached, as the listening screen does ([9971309](https://github.com/wquguru/cicada/commit/9971309beef23573cc6dc0a789dca0b4aba4bfc5))
- While the first notes are being written, the notes page keeps its placeholder with a spinner and how many lines it heard, as on the Mac ([29b64c3](https://github.com/wquguru/cicada/commit/29b64c337f9612e74078f30541c943be8a37ec9d))
- The intro guide's In person card says that with people online you put the meeting app on speaker, as Home does ([04debe0](https://github.com/wquguru/cicada/commit/04debe09ba9fde1d139fd228ec0df2508f52fb8b))
- Translations heard by the AI service no longer start with a note about which language the meeting is in ([c6e02ee](https://github.com/wquguru/cicada/commit/c6e02ee6bd095ab9b282a14d41aa275cc72e18b8))
- A long meeting's live notes no longer give a topic a start time minutes after what was said in it ([1010793](https://github.com/wquguru/cicada/commit/101079358c2983f811a41e08cb0235b37b316490))

### Linux

#### New

- Listen to › Room hears the people at the table through a microphone ([1ca0df6](https://github.com/wquguru/cicada/commit/1ca0df6e2a99ccd5fd1821c8ca50b0c7895997bc))
- Listen to › Computer + Room hears people online and at the table together, and marks each line In room or Online ([1bafda0](https://github.com/wquguru/cicada/commit/1bafda07870f402f4576561cf98fe20b9253ed04))
- When the AI service needs you to fix something, like a key that stopped working, the top-bar icon shows an orange dot and one notification per meeting says so if the notes window is put away; an outage gets one after 2 minutes ([20b04b6](https://github.com/wquguru/cicada/commit/20b04b6c95fe0947ab7c33de559eb9f96d8175de))
- Your own AI server can be set per job, on a LAN or Tailscale address over http with no key, and its check says when the model thinks before answering ([6fbdcd0](https://github.com/wquguru/cicada/commit/6fbdcd0888215268c50d6e723a2acaf8544e1b91))
- Scrolling down a meeting record keeps its title and the Notes / Transcript tabs on top, and clicking the title goes back to the start ([878f6d4](https://github.com/wquguru/cicada/commit/878f6d4445177682e89b9b65e53b2df13d50083b))

#### Fixed

- A meeting's lines keep whether they were heard in the room, so a Mac + Room record opened on Linux stays the same ([5e95698](https://github.com/wquguru/cicada/commit/5e956985c0467509936bc5bc6afdb64cca3b99a8))
- A very quiet voice in a meeting is no longer mistaken for a fan or hum and left without subtitles ([bc2ae04](https://github.com/wquguru/cicada/commit/bc2ae04adec9bd044273738ff9f3af9be0c65f04))
- A busy moment at Ling no longer loses meeting lines ([73113a6](https://github.com/wquguru/cicada/commit/73113a66fb584d13338a12939720572de585f4a0))
- Cicada uses the proxy set in Settings › Network › Network Proxy, and says when that proxy doesn't answer or is Automatic ([8c2784a](https://github.com/wquguru/cicada/commit/8c2784a6f252e1852f20118970ff905eb2875ec8))
- A slow or cut-off update download resumes instead of failing, and if it still fails Cicada says whether the download page really opened ([cdeae31](https://github.com/wquguru/cicada/commit/cdeae316bf3d8065304e1e604ebeda23bc97db0c))
- The Rewrite in <language> button puts spaces around a Latin language name in Chinese ([2ae4563](https://github.com/wquguru/cicada/commit/2ae4563e42631b5d4025c1b8ed31d308006f43bd))
- A short word on its own, like "Thanks." or a quiet "Good morning everyone" is no longer dropped ([c7d3d19](https://github.com/wquguru/cicada/commit/c7d3d19eaf2435288183ce6112adc99f6afb48c0))
- Low rumble such as brown noise no longer turns into made-up meeting sentences ([7d1eaa7](https://github.com/wquguru/cicada/commit/7d1eaa7eb88bac9904053e588c89b1c19650a302))
- While no notes are out yet, the notes window shows the listening placeholder and how many lines it heard ([fe6f229](https://github.com/wquguru/cicada/commit/fe6f22947a49821a4bf1bca5a69e2f338051b7ad))
- A key the check refused shows as invalid in the notes window instead of an idle wait ([e7eacfb](https://github.com/wquguru/cicada/commit/e7eacfbd31b7682996e067ebea4255dc37eddeb7))
- Live notes keep updating through hours-long meetings without one topic swallowing the rest, and a long meeting's full notes cover all of it ([0ec2628](https://github.com/wquguru/cicada/commit/0ec26288efc5bdc21253fec06e82957fbc2ed733))
- The notes window no longer says notes stopped at 00:00 when only another request lost the network, or while you look at an earlier meeting ([e1dc39e](https://github.com/wquguru/cicada/commit/e1dc39e5a749c302c105aa5f6332fb48acb7fb16))
- Someone typing during a pause no longer joins the sentences either side into one ([f1fbf83](https://github.com/wquguru/cicada/commit/f1fbf83ed5982edab2c0b96af1b699219be6b7a1))
- The rows of your own AI server in Settings › AI Service line up on the left instead of floating in the middle ([60adf4c](https://github.com/wquguru/cicada/commit/60adf4c74966bc528eb94c248db84e4e8f835d84))
- Opening Settings again while it is open no longer adds a second key field under your own AI server ([46239cf](https://github.com/wquguru/cicada/commit/46239cf35f7f877d0491c5fa1a4c3149399a008c))
- Checking your own AI server says its model thinks first even before a listening model is filled in ([650bcdd](https://github.com/wquguru/cicada/commit/650bcddd87238a99fb8208eef289a9a01be0fbbc))
- An AI service problem in the notes window or a notification no longer says the same sentence twice, and names the service when no listening model is set ([ad65c0b](https://github.com/wquguru/cicada/commit/ad65c0bbf8cc092019981b352313ab3f880ecff6))
- The bar that stays on top of a scrolled meeting record also keeps Bilingual / Translation only ([3830c34](https://github.com/wquguru/cicada/commit/3830c348318b481ad5652d7a8df62c669d2e40c6))
- Switching to Listen to › Computer + Room mid-meeting times the room's lines in the meeting instead of at 00:00 ([cc5ca3b](https://github.com/wquguru/cicada/commit/cc5ca3b334d209e19eb2587bfd9019e9a7ec5340))
- Translations heard by the AI service no longer start with a note about which language the meeting is in ([8413c00](https://github.com/wquguru/cicada/commit/8413c009e877f43ece95b2b0b3956f5ee8bfb814))
- The key field of your own AI server is wide enough to read its hint in English, Japanese and Korean ([96e714b](https://github.com/wquguru/cicada/commit/96e714babb1165bd086b6210fdae25657f8f74d2))
- A long meeting's live notes no longer give a topic a start time minutes after what was said in it ([4187d08](https://github.com/wquguru/cicada/commit/4187d08eb52c5f5609e79fd47818f2f8144ecc57))
- The switch-source menu in the live notes window opens and works instead of freezing the app ([1d3169c](https://github.com/wquguru/cicada/commit/1d3169c0d2097d8f116024e9c6fb7273e50bf03a))
- A server on the local network that can't be reached no longer gets advice to turn on a proxy ([1c4c5d0](https://github.com/wquguru/cicada/commit/1c4c5d011c8fbfaf4c270a76df1c85991242b7d8))

### Website

- Hovering the menu no longer makes the header flash ([aa6ec79](https://github.com/wquguru/cicada/commit/aa6ec7939ec09de91d4550ff1ac5821c62a686ad))

## 1.2.1 — 2026-11-05

Everything in [1.2.0](#120--2026-11-05), which was not published on its own, plus the fixes below.

### Mac

No changes; released to keep every platform on the same version.

### Windows

#### Fixed

- Quiet speech in a meeting is no longer mistaken for a fan or hum and left without subtitles ([e3c8b72](https://github.com/wquguru/cicada/commit/e3c8b723fccaf902e36ca2dcc051578926cc5761))

### Android

#### Fixed

- Quiet speech in a meeting is no longer mistaken for a fan or hum and left without subtitles ([0a14926](https://github.com/wquguru/cicada/commit/0a14926ec6ab09dadd2e925b2b83166b3687d675))

### Linux

#### Fixed

- Quiet speech in a meeting is no longer mistaken for a fan or hum and left without subtitles ([ed57f8f](https://github.com/wquguru/cicada/commit/ed57f8faddd922e2b461c7e5dfff46249847f037))
- Settings shows the field for typing an AI service key again, so a key can be added or changed there ([9126e15](https://github.com/wquguru/cicada/commit/9126e150266cba978f04405747d597d08a9d3bd9))

## 1.2.0 — 2026-11-05

### Mac

#### New

- When the AI service fails, Settings shows which step broke and how to fix it ([21a0f7a](https://github.com/wquguru/cicada/commit/21a0f7aad9f4538e58c462f6454c0dab3cc9acc2))

#### Fixed

- Subtitles no longer show a lone "Translate" when Ling translates its own instruction instead of the line ([0984b75](https://github.com/wquguru/cicada/commit/0984b750fab63a13688dc6be4ce7fcb62d7dfe97))
- Keep trying for about a minute when the AI service is busy as a meeting's final notes are written ([7707626](https://github.com/wquguru/cicada/commit/7707626623de366ab04d342a5d11faab03c35f2c))

### Windows

#### New

- Use OpenRouter, ZenMux or any OpenAI-compatible service when Ling isn't an option ([222f8f9](https://github.com/wquguru/cicada/commit/222f8f9e87bdea2239c3a690e6d71e4260ca5143))
- When the AI service fails, Settings shows which step broke and how to fix it ([1664a74](https://github.com/wquguru/cicada/commit/1664a7409aeb8014e1b995dbcd31cd1598561205))

#### Fixed

- Subtitles no longer show a lone "Translate" when Ling translates its own instruction instead of the line ([224b2ed](https://github.com/wquguru/cicada/commit/224b2ede72fd1a7ede7252f228e8cfa59617e389))
- A fan, hum or hiss no longer turns into a made-up English sentence ([ca9d86a](https://github.com/wquguru/cicada/commit/ca9d86a777503a6cd69843a794c56779aab6fc51))
- Windows downloads are named like the other platforms' (Cicada-<version>-Windows-x64.exe / -ARM64.exe), with no zips ([61ff770](https://github.com/wquguru/cicada/commit/61ff770075360d274cb365326b6372f3b4662909))

### Android

#### New

- The floating window has a button that goes back to the listening screen in Cicada ([0af03b8](https://github.com/wquguru/cicada/commit/0af03b8e29d8169959132abf47b99ccb25819ce6))
- Use OpenRouter, ZenMux or any OpenAI-compatible service when Ling isn't an option ([b8a49fa](https://github.com/wquguru/cicada/commit/b8a49fa8e6482021a0bf065abe78762a12ab0758))
- When the AI service fails, Settings shows which step broke and how to fix it ([3d80833](https://github.com/wquguru/cicada/commit/3d808339d39ba673eec90c67e31f41b589fe74b8))

#### Fixed

- Subtitles no longer show a lone "Translate" when Ling translates its own instruction instead of the line ([de9c06c](https://github.com/wquguru/cicada/commit/de9c06c1b2509a4265f222507f4a013a14c14775))
- A fan, hum or hiss no longer turns into a made-up English sentence ([ba91e37](https://github.com/wquguru/cicada/commit/ba91e37d3a023c2fa1a7cc70bdd8ec478f771605))

### Linux

#### New

- Use OpenRouter, ZenMux or any OpenAI-compatible service when Ling isn't an option ([a1ba49e](https://github.com/wquguru/cicada/commit/a1ba49e703da2da01e149c12dd502d8a83c33139))
- When the AI service fails, Settings shows which step broke and how to fix it ([c3f2a69](https://github.com/wquguru/cicada/commit/c3f2a699a2979bf2ceb1f679d8b8d5bd2a7e997e))

#### Fixed

- Subtitles no longer show a lone "Translate" when Ling translates its own instruction instead of the line ([4208271](https://github.com/wquguru/cicada/commit/4208271d3de8140138eaf430cc73a1a8ae30e2dd))
- A fan, hum or hiss no longer turns into a made-up English sentence ([a432905](https://github.com/wquguru/cicada/commit/a432905a90e84d02081778843f1fd62b406ee2f4))

### Website

- The setup page offers OpenRouter beside Ling for the Mac, and says what to do when Ling isn't an option ([a3044cc](https://github.com/wquguru/cicada/commit/a3044cc82fc32485a655894c9f69ab73a8cc55b0))
- The Windows download buttons no longer squeeze their x64 / ARM64 hints onto two lines ([cc80cb6](https://github.com/wquguru/cicada/commit/cc80cb619ad83c7414557ade23d60b786d6baf7a))
- The share cards name Mac, Windows, Linux and Android instead of macOS alone ([0b67482](https://github.com/wquguru/cicada/commit/0b674821709f42b9457740f6293a2d577e087922))

## 1.1.1 — 2026-11-04

### Android

#### Fixed

- Show the first-run setup screens again; they opened blank with only the Continue button ([c5acd7d](https://github.com/wquguru/cicada/commit/c5acd7da6c129baedc84eeff925ca2194b13a19c))

## 1.1.0 — 2026-11-04

### Mac

#### New

- Keep the "show when sharing screen" lamp in the notes window so one click turns it on or off ([10cd9f0](https://github.com/wquguru/cicada/commit/10cd9f0401ec288fd73ec52c1e67662fe2affd2a))
- Check for updates every 4 hours and from the menu bar panel, with the result shown in place ([76677e0](https://github.com/wquguru/cicada/commit/76677e00f4b37c72aa4dda665b39288aa37c05b0))
- Run on macOS 14.4 and 15, with the older on-device speech recognizer ([900c36e](https://github.com/wquguru/cicada/commit/900c36e3ac1c23a303590197db2d7b11d1bd6b7d))
- Listen to a meeting in the room through the Mac's microphone (听哪里 › 会议室) ([9236b26](https://github.com/wquguru/cicada/commit/9236b267fc15993b0a9caa2726f859c9709a9c23))
- Import a recording or video and turn it into a meeting record ([6f6eba2](https://github.com/wquguru/cicada/commit/6f6eba22cd4fe6f3ca36a182bedd0ad47a0bee12))
- Turn speaker identification on by default, out of 实验功能 and into 设置 › 通用 ([d0e8924](https://github.com/wquguru/cicada/commit/d0e89245eabeed0e0c71ceb2729faa6aec601d8e))
- Rename speakers, merge them or give a paragraph to someone else right in the live notes window ([b3e09a9](https://github.com/wquguru/cicada/commit/b3e09a9cbdd5b28a99f25823e235378463063667))
- Make the notes window's yellow button tuck it away to the menu bar, like 收起 ([89ecdff](https://github.com/wquguru/cicada/commit/89ecdffb8e7d112051707a1205e4a17a5d0d0708))
- Click 正在听 at the top of the records window to bring back the live notes or subtitle bar ([366cee0](https://github.com/wquguru/cicada/commit/366cee04c2f976ab954fbbe4c86e3d06863979e7))
- Say how far the notes are behind the meeting, and lay out the live notes window to read more easily ([32319e6](https://github.com/wquguru/cicada/commit/32319e68bf096cccff959edb22d39c9dd122fdd0))
- Switch AI Service to OpenRouter, ZenMux, OpenAI or any OpenAI-compatible service when Ling isn't an option ([e774220](https://github.com/wquguru/cicada/commit/e77422009e1baa3285afe4561cfc9818b292bdc1))
- A meeting whose language was never recognized keeps its recording, and you pick the language to transcribe it ([e31191e](https://github.com/wquguru/cicada/commit/e31191e8e34cd3c0d31d0cea74575ff94cb25bb2))
- Diagnostics shows each AI request by service, model and use, with time to first audio for the translated voice ([16d70e6](https://github.com/wquguru/cicada/commit/16d70e686fc7cd9b7fa55527999e98f4e4d80a41))
- Show a new version at the top of the menu bar panel and send one notification per version (held while a meeting is on), with a clearer dot on the menu bar icon ([bc68dfe](https://github.com/wquguru/cicada/commit/bc68dfef9d111447883d9a4983970ec512cef104))

#### Fixed

- Drop Ling's remarks about a garbled line instead of showing them as the translation ([9641ae4](https://github.com/wquguru/cicada/commit/9641ae437194336f274203d72d7da9c8a6afc555))
- Keep the words fast speech loses when a long line is ended ([2893a02](https://github.com/wquguru/cicada/commit/2893a023177dc3f1f702610013c411884f50beaa))
- Catch Ling's notes, Chinese remarks and leaked reasoning in translations, and keep quotes intact ([89e1727](https://github.com/wquguru/cicada/commit/89e1727c74a6a58b329e5d6aa61a97a6e6aa5d4f))
- Retry a sentence's translation when Ling, Google and the on-device model all fail ([0fe488c](https://github.com/wquguru/cicada/commit/0fe488cff49af9d6063d7ed9b77ac964a6ca3b4c))
- Switch to English within seconds when it follows Chinese with no pause ([d9c4462](https://github.com/wquguru/cicada/commit/d9c44626f67b7b13ab39497d3be8c9faa7ca9e31))
- Read what the Mac plays, not the microphone, when sound goes out through a device with one (a USB headset, AirPods) ([283dc5f](https://github.com/wquguru/cicada/commit/283dc5f71265672929a23fbb1c02cc8b828d22c0))
- Stop sticking on 正在识别语言 when only one speech model is installed ([328e250](https://github.com/wquguru/cicada/commit/328e2502053b87e7bc6022b078bff3cc32e811b5))
- Wrap long names and terms in 人名和术语 instead of running past the window ([e0ef1a5](https://github.com/wquguru/cicada/commit/e0ef1a56bd1a928347b8d3b1d7db6e039b32a00a))
- Keep the live transcript where you scrolled it on macOS 14 instead of jumping to the newest line ([ba85696](https://github.com/wquguru/cicada/commit/ba8569674b731e570b988facc15a82f39cc8872d))
- Keep every line on macOS 14 and 15 when a file is imported while a meeting is being listened to ([3a2a8c6](https://github.com/wquguru/cicada/commit/3a2a8c6e68fb897dbfc5ca4f9bd9e80365f0df41))
- Record meetings in the one Dictation language on macOS 14 and 15 instead of asking which language it is ([84ab3a1](https://github.com/wquguru/cicada/commit/84ab3a167819bd6a3b2791a10983e2d67b781b6e))
- Keep two speakers' lines apart on macOS 14 and 15 instead of joining them into one ([d354fa6](https://github.com/wquguru/cicada/commit/d354fa6df66cd32af5f1fc58b9e794a361ed5c01))
- Say a language added to Dictation works once it has downloaded, on macOS 14 and 15 ([317b98e](https://github.com/wquguru/cicada/commit/317b98efc790ba6f5ac5fd9d385871ee8d7c8634))
- The translated voice no longer goes silent for the rest of the meeting after the output device switches ([15a47a6](https://github.com/wquguru/cicada/commit/15a47a6d3472b8a796cadf0d93913331dc6e32d0))
- A cloned voice recorded too slowly is caught and flagged, so your translated voice no longer drags ([8e27bb0](https://github.com/wquguru/cicada/commit/8e27bb0429fca346706d24161c67d6faba9eddd4))

### Windows

#### New

- Speak into the meeting in its language: hold right Ctrl, the room hears the translation ([5844255](https://github.com/wquguru/cicada/commit/584425553f3f7e59e06de1ef7ae0c4400c01ac83))
- Label the other side's lines Speaker 1, 2… by voice, on this PC only ([0479977](https://github.com/wquguru/cicada/commit/04799773757062694a311bebec1fb73e703dc4e9))
- End a meeting by itself when the meeting app hangs up or nobody has spoken for a while ([e491656](https://github.com/wquguru/cicada/commit/e491656b39b0c1ca558b5819361494ca71c4b48a))
- Tell you when a new version is out and download the right one for your PC ([7d92199](https://github.com/wquguru/cicada/commit/7d921996c43aa2bcdae632113cc193050c405472))
- Install with one Cicada-Setup.exe, no admin rights, and upgrade the same way ([059a18c](https://github.com/wquguru/cicada/commit/059a18ca89a6f5312040a81375866ad620b9ac0a))
- Open to a main window that says what's left to set up, with a listening switch in the title bar ([1446b24](https://github.com/wquguru/cicada/commit/1446b24179e69a8927476ccadb2f63bc952eb87f))
- Windows now shows a dot on the tray icon and a notification for a new version, and installs it in one click without a SmartScreen warning ([a70eecb](https://github.com/wquguru/cicada/commit/a70eecbe0fbe02bddb2611f28a52c2334f035749))

#### Fixed

- Keep Mac records intact, ask before ending a meeting, and show when notes fail ([ced2825](https://github.com/wquguru/cicada/commit/ced28259520edb55eb5a016d819f8e1930cdfab1))
- Hold music, ringback tones and typing no longer show up as lines of filler words ([2f44821](https://github.com/wquguru/cicada/commit/2f44821a6be5f93edf4a772d288b1be84455de70))

### Android

#### New

- Redesign the app on the iPhone design, with saved meeting audio, export, import, speaker names and a full-screen face-to-face view ([b556497](https://github.com/wquguru/cicada/commit/b556497e57d3a3514196a87601e8750631e59068))
- Android now tells you when a new version is out and updates from the browser ([458324b](https://github.com/wquguru/cicada/commit/458324bafdb4e013f35708e8344d99682b34db8d))

#### Fixed

- Stop showing a meeting's first line twice ([658cc8e](https://github.com/wquguru/cicada/commit/658cc8e872273640e5ccb024a3898f081410e9c9))
- Follow the system language as the Mac does when they speak yours ([e3dcb11](https://github.com/wquguru/cicada/commit/e3dcb1131c4a4b4a73197aa40723e3e9077d872b))
- Keep the floating window from covering a picture-in-picture video after Watch over video ([22577bb](https://github.com/wquguru/cicada/commit/22577bbdc631129393feee966772789eb7f7423c))
- Hold music, ringback tones and typing no longer show up as lines of filler words ([7f07ee8](https://github.com/wquguru/cicada/commit/7f07ee838ba8d6827d46d391b431a599bccc8252))

### Linux

#### New

- Add the Linux app for Ubuntu with live notes, meeting records and Interpreting ([9216708](https://github.com/wquguru/cicada/commit/9216708960789fe0fab72ab877390c11a2d508de))
- Tell you when a new version is out and update in place with one click ([c8fd226](https://github.com/wquguru/cicada/commit/c8fd22613741554778b07c7ee864e9c798e03071))
- Open to the records window with a checklist of what's left to set up, and a test sound for the computer's audio ([e5c14eb](https://github.com/wquguru/cicada/commit/e5c14eb731df43317565ee83ffa44df771c3c6e2))
- Linux now shows a dot on the top bar icon and a desktop notification for a new version (held while a meeting is on); clicking it installs ([adc9d5e](https://github.com/wquguru/cicada/commit/adc9d5e3bad14e48a361456e5afa06d5ec80d30f))
- Change one meeting's notes language from the live notes window, and pick my language or the meeting's own in Settings, as on the Mac ([8bc6f81](https://github.com/wquguru/cicada/commit/8bc6f81264f6dc3a0f6d21328cb19007440eaf03))

#### Fixed

- Hold music, ringback tones and typing no longer show up as lines of filler words ([3a6e5e5](https://github.com/wquguru/cicada/commit/3a6e5e5e094fa3f19f77475d33de6469605ab644))

### Website

- Say Cicada runs on macOS 14.4 and later ([912781c](https://github.com/wquguru/cicada/commit/912781c6ea2c53aa7a4ef592e1422f324633f66e))
- Show the share card in the page's language when a link is shared ([10cad54](https://github.com/wquguru/cicada/commit/10cad54b313d0de4c853e4a6d96df6d8edcb4e5c))
- A download page for every platform, setup steps per platform and a changelog filter by platform ([1e4af22](https://github.com/wquguru/cicada/commit/1e4af22bf63d369c03e6787656ea5185cb411de5))
- Rewrite the 1.1.0 changelog and homepage copy ([9179573](https://github.com/wquguru/cicada/commit/91795735014ad5e39523038cd31e1ced00612f37))
- Describe Cicada by what it does rather than as a menu bar tool ([38771f1](https://github.com/wquguru/cicada/commit/38771f1a5ae691c848ea429f4a870defd92d9d26))
- Say Android shows the speakers Mac and Windows found instead of telling voices apart itself ([ab1d748](https://github.com/wquguru/cicada/commit/ab1d7489c1d4405765590b2607372a3f50e070ed))

## 1.0.0 — 2026-11-03

The first public release. Cicada turns whatever your Mac plays into live translated subtitles and meeting notes, keeps each meeting as a bilingual record, and speaks what you say back into the meeting in the other side's language.

### Highlights

- Live bilingual subtitles for any app that plays sound, with on-device speech recognition that detects the spoken language
- Live meeting notes with a Ling key: a summary, topics, conclusions, to-dos, names and terms, and a fishbone diagram when causes are discussed
- Meetings saved as bilingual records with the notes beside the original lines, exported to Markdown, Word or SRT, and ended by themselves when the call hangs up or goes quiet
- Interpreting: hold right ⌥ to talk, and Cicada speaks the translation into the meeting through BlackHole 2ch with a Ming voice, a Mac voice or your own, switching the system mic for you
- Speaker identification (experimental) tells the other side's voices apart and, with a Ling key, fills in their names
- The live notes window stays out of screen sharing unless you choose to show it
- English, Japanese, Korean and Chinese interface, a four-step first-run guide, and in-app updates checked against each release's SHA-256
