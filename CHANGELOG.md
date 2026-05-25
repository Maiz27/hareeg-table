# Changelog

## [1.0.0-alpha.7](https://github.com/Maiz27/hareeg-table/compare/v1.0.0-alpha.6...v1.0.0-alpha.7) (2026-05-25)


### Features

* **cards:** add Iron Rose theme ([14189cf](https://github.com/Maiz27/hareeg-table/commit/14189cf9a2e6537283b9efcf6bf5e531c5cb0668))


### Bug Fixes

* **cards:** replace sandline jack of diamonds art ([9ef9afb](https://github.com/Maiz27/hareeg-table/commit/9ef9afb2f289cfe06349ddba5cb8579d84861392))
* **cards:** restore sandline jack asset via manifests ([abc277d](https://github.com/Maiz27/hareeg-table/commit/abc277dd7b4b598fe07e4a242c27b101e14e3548))
* **domain:** preserve joker cover edge intent ([d19f980](https://github.com/Maiz27/hareeg-table/commit/d19f980d3328c26c143ba9872e7c650a24ce4be7))
* **game:** checkpoint active turns for resume ([a5a4b79](https://github.com/Maiz27/hareeg-table/commit/a5a4b795439032c605df20d4a1ddbbc8ba2a04a5))
* **game:** rebase cover-play indices when a meld is removed ([4282c71](https://github.com/Maiz27/hareeg-table/commit/4282c71637593d1c68a86192255b7d15d3572115))
* **persistence:** persist DiscardHistory so resumed matches keep CPU memory ([a922bcf](https://github.com/Maiz27/hareeg-table/commit/a922bcf8e0cde3f5f1bcfc9804116872f8662a36))

## [1.0.0-alpha.6](https://github.com/Maiz27/hareeg-table/compare/v1.0.0-alpha.5...v1.0.0-alpha.6) (2026-05-24)


### Features

* **match:** short-circuit to MatchOver when human is eliminated by score ([8a35f92](https://github.com/Maiz27/hareeg-table/commit/8a35f927202d5983a8dd1614710594fa9e1ad72d))
* **ui:** spectator shortcuts — match short-circuit + Table fast-forward ([7043319](https://github.com/Maiz27/hareeg-table/commit/704331988d19ed438ff706bff8bc527724a5aac5))
* **ui:** table-tier fast-forward button when human is out of the round ([edbd091](https://github.com/Maiz27/hareeg-table/commit/edbd09195d1ad03e9df9192d79c8ece4e8bb29b0))


### Bug Fixes

* **cards:** bypass miswired jack_diamonds asset in Sandline Lounge ([5161033](https://github.com/Maiz27/hareeg-table/commit/5161033e15dc554257f4bfcc8acb1e21a0a52ec9))
* **cards:** drop mislabelled jack_diamonds art and add face-asset consistency test ([a33ddfb](https://github.com/Maiz27/hareeg-table/commit/a33ddfb57418cf9fdbbe33f09e758cd376831666))
* **rules:** block CPU mistake-class actions when cpuMistakesAllowed is false ([8b9d284](https://github.com/Maiz27/hareeg-table/commit/8b9d2843c28d774a377c73f23cf5074035641d4b))
* **rules:** refuse CPU mistakes when cpuMistakesAllowed is false ([76c5c19](https://github.com/Maiz27/hareeg-table/commit/76c5c19dbaddde19c8663ffccdfd0c5c5c8381e1))
* **ui:** drop dead _isJokerCueActive reference after [#41](https://github.com/Maiz27/hareeg-table/issues/41) + [#47](https://github.com/Maiz27/hareeg-table/issues/47) merge ([27a896b](https://github.com/Maiz27/hareeg-table/commit/27a896bb36a148f262eb72031ddfcb7874fad87a))
* **ui:** drop dead _isJokerCueActive reference in _fastForwardRound ([5c286ca](https://github.com/Maiz27/hareeg-table/commit/5c286cae361e41f35d6170c9edd4c2c76ce4d584))
* **ui:** keep expanded meld stack fully visible past the hand boundary ([a28c470](https://github.com/Maiz27/hareeg-table/commit/a28c470b171da40884967c3e5e4f15d0f6e25b68))
* **ui:** keep expanded meld stack visible past the south hand boundary ([a8e33fc](https://github.com/Maiz27/hareeg-table/commit/a8e33fc370bb8afa698f094ae5c93cbd1da717cc))
* **ui:** make meld confirm rack tier-independent ([458f983](https://github.com/Maiz27/hareeg-table/commit/458f9834105c5458d066957f612d5fd2dc3ebb4c))
* **ui:** make meld confirm rack tier-independent ([b05f69e](https://github.com/Maiz27/hareeg-table/commit/b05f69eff59d492d019790e1092702d5c6a03977))
* **ui:** restore meld confirm surface for valid selections ([a17c7fe](https://github.com/Maiz27/hareeg-table/commit/a17c7fe5e7c202955cea79c9a7c51aa0b2a2b934))

## [1.0.0-alpha.5](https://github.com/Maiz27/hareeg-table/compare/v1.0.0-alpha.4...v1.0.0-alpha.5) (2026-05-24)


### Features

* **cpu:** add Skilled/Expert/Priority planners with observation-aware strategy ([5870064](https://github.com/Maiz27/hareeg-table/commit/587006432714e6c1dcecbf30635edadfd656960e))
* **rules:** add TableStrictness with mistake handling, meld partition, and discard history ([81e6d96](https://github.com/Maiz27/hareeg-table/commit/81e6d96aa90536e72f4bbcbb42e1be19d5ab4670))
* **ui:** meld flight, joker reveal, match-over screen, and strictness pickers ([4042fcd](https://github.com/Maiz27/hareeg-table/commit/4042fcd983d763324d927de5efc0a541f50efaa9))


### Bug Fixes

* **audio:** stagger startup warmup and add joker / meld cue events ([63bfa56](https://github.com/Maiz27/hareeg-table/commit/63bfa56a60fec10df5a71fbae200babefe11d139))
* **rules:** address review nits across enumerator, ui flow, audio chain, and tests ([9946d58](https://github.com/Maiz27/hareeg-table/commit/9946d58ef5bb6301e0ff0db1de06475d53bca1ee))
* **ui:** clear joker cue queue on round advance ([f5db30d](https://github.com/Maiz27/hareeg-table/commit/f5db30de6e63013f9d24806d0c7199536842dc14))

## [1.0.0-alpha.4](https://github.com/Maiz27/hareeg-table/compare/v1.0.0-alpha.3...v1.0.0-alpha.4) (2026-05-23)


### Features

* **settings:** replace auto-sort toggle with hand-sort-mode picker ([8ee12ff](https://github.com/Maiz27/hareeg-table/commit/8ee12ff149fbafeef53fd538b19e84802d9dcb5a))


### Bug Fixes

* **rules:** address review nits across meld search, retraction, and audio ([1c02d8c](https://github.com/Maiz27/hareeg-table/commit/1c02d8cb95aa7615be5f0fb03aea2aac54b490b2))
* **settings:** move card sorting into its own accordion section ([d17be23](https://github.com/Maiz27/hareeg-table/commit/d17be237f2a814967c8246beac8c3f507c39b7f1))

## [1.0.0-alpha.3](https://github.com/Maiz27/hareeg-table/compare/v1.0.0-alpha.2...v1.0.0-alpha.3) (2026-05-22)


### Features

* **audio:** introduce TableAudio gateway with preloaded SoundPool seam ([dfdcb29](https://github.com/Maiz27/hareeg-table/commit/dfdcb2930bfe0dda626ce5a5ca74af76e176d6fd))
* **cards:** add motion seam to ShowcaseCardFan ([a582948](https://github.com/Maiz27/hareeg-table/commit/a582948ca12828806ae683c669a31d44ca54c3e0))
* **cards:** inline suit glyph on the represented-joker badge ([3b507fa](https://github.com/Maiz27/hareeg-table/commit/3b507fa03122bef4194cc05d8d9aec326416134c))
* **game-table:** place the fifty cue above the discard pile ([5840032](https://github.com/Maiz27/hareeg-table/commit/5840032c17ad3d4ee4f6942af5bc9b2e667f9c3e))
* **home:** looping idle motion on the showcase fan plus breathing room ([b32e28a](https://github.com/Maiz27/hareeg-table/commit/b32e28a0a051ea990d22de78e8f6c13f06294596))
* **licenses:** credit Kenney casino audio in About + Licenses ([d65b7f9](https://github.com/Maiz27/hareeg-table/commit/d65b7f98321fad52a81b4d20bb1c8fef0de9ae23))
* **prefs:** default table sound to on with versioned migration ([fce03fe](https://github.com/Maiz27/hareeg-table/commit/fce03fe2b773c6d06eb43f9b1f78eaa0c5525adc))
* **splash:** play the take-out cue on splash mount ([bbacd58](https://github.com/Maiz27/hareeg-table/commit/bbacd581468030e3f5c2d7d4391224edde5bef38))


### Bug Fixes

* **audio:** make audio dispose paths absorb player errors ([6518391](https://github.com/Maiz27/hareeg-table/commit/65183913473a2a9fd7b71f3d651c3ac22e327956))
* **audio:** wrap audio gateway dispose Future in error handling ([ab58b67](https://github.com/Maiz27/hareeg-table/commit/ab58b67b5c6dfc9278d476888eca63978a50b98b))
* **cards:** refresh ShowcaseCardFan duration when motion speed changes ([d627fbe](https://github.com/Maiz27/hareeg-table/commit/d627fbea00b00a9866ea64e6d6b4d4e23de2a79d))
* **game-table:** handle zero-duration flights in dealStepProgress ([deae24b](https://github.com/Maiz27/hareeg-table/commit/deae24bce91152ae99186640b61ac896aa2f8f5a))
* **game-table:** lock human controls during pre-apply flight ([f54cbea](https://github.com/Maiz27/hareeg-table/commit/f54cbea1a67a42437d1fe7d027b1931296141db0))
* **rules:** keep the fifty cue visible during expiry grace window ([7e4578a](https://github.com/Maiz27/hareeg-table/commit/7e4578ac70e34c30fe5005eef3b98c7940cff22b))

## [1.0.0-alpha.2](https://github.com/Maiz27/hareeg-table/compare/v1.0.0-alpha.1...v1.0.0-alpha.2) (2026-05-22)


### Bug Fixes

* **release:** repair alpha APK publishing ([3061051](https://github.com/Maiz27/hareeg-table/commit/306105120eb254b2aa6a9f3a96364b5d5f653c84))

## 1.0.0-alpha.1 (2026-05-21)


### Features

* **release:** automate alpha APK releases ([e348055](https://github.com/Maiz27/hareeg-table/commit/e348055ad01f288150a4b007aecb19b19278e3e3)), closes [#27](https://github.com/Maiz27/hareeg-table/issues/27)

## Changelog

All notable changes to Hareeg Table will be documented in this file.

This project uses Release Please to update the changelog from Conventional Commits.
