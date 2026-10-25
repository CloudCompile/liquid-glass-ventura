# Project memory — anime-api

## NyAnime web app — Liquid Glass UI (2026-10-24)
Whole-site Apple Liquid Glass via vendored `dashersw/liquid-glass-js`
(`public/liquid-glass/`, byte-identical to upstream; loaded as plain scripts from
`index.html`). `src/lib/liquidGlass.ts` is the bridge: any element with
`.glass` / `.glass-card` / `.glass-surface` gets a live WebGL surface, picked up by
a MutationObserver so later mounts and re-classing work too.
Requested settings are pinned as `GLASS_SETTINGS` in that file and verified live
(58 instances / 8 routes / 0 uniform mismatches).

Traps worth remembering:
- `@layer components` must live in `src/index.css` (the file with
  `@tailwind components`); using it in another CSS file makes Tailwind 500, which
  surfaces as a `vite-error-overlay` crash rather than a CSS error.
- The library caches one `html2canvas` snapshot of `document.body` forever, so an
  SPA freezes the glass at its boot screenshot. `window.__nyanimeRefreshGlass`
  (called on route change) nulls it and re-mounts surfaces.
- Never mutate the `managed` Set while iterating it in the enhancer — re-adding a
  host during iteration hangs the main thread.
- `setupShader` reads `rimIntensity || 0.05`, so rim 0 needs re-applying after the
  shader is built.
- `verify-playback.mjs` needs a **slug** id (`NYANIME_URL=.../anime/naruto-76396/watch`);
  its numeric default cannot resolve via `/api/episodes/` and times out.

See `.openhands/memory/2026-10-24.md` for the full log.

## Environment quirks
- No `dig`/`host` in the container; use Python `socket.getaddrinfo` or DoH
  (`cloudflare-dns.com/dns-query`, `dns.google/resolve`) for DNS checks.
- Many scraping targets sit behind Cloudflare Turnstile or ParkLogic parking. A
  200 response with a tiny body (~3-7 KB) and title "Just a moment...",
  "Redirecting...", or "This domain is for sale" is NOT a working site. Always
  dump visible text, not just the status code.
- Cloudflare sometimes serves an SSL chain curl cannot verify
  ("unable to get local issuer certificate") — re-probe with `curl -k` before
  declaring a host dead.
- Parallel probing triggers rate-limiting that looks like `000`/timeout; confirm
  flaky hosts serially.
- When scraping with `subprocess` + `text=True`, pass `errors="replace"` — some
  anime pages are non-UTF8 and will crash the call otherwise.

## Verified-live scraping sources (as of 2026-10-21, US datacenter IP)
Streaming: 9anime.si, animetake.tv, animelon.com (JS SPA), hianime.io, hianime.si,
hianime.com.pk (->hianimeb.de), kawaiifu.org, animekaizoku.click,
watchcartoononline.com, wcostream.tv, wco.tv, wcoanimedub.tv, kimcartoon.com.co,
anitube.biz, anitube.online.
Download (DDL): animechiby.com, anidl.org, anime2enjoy.com, darklegends60mb.org,
hi10anime.com, erai-raws.info (login-gated).
Dead/parked: animepahe.* , anime8.ru, animehub.ac, animedao.*, watchcartoononline.io,
aniwatch.tv/.io, 9anime.vc, animevibe.ru, justdubs.org, chihiro-subs.com, kaa.si,
kawaiifu.com/.net/.me, animedubbed.*, simpleyaweeb.com, anichiraku.ru, aniwatch.me.

## Domain-history fact
zoro.to -> aniwatch.to -> HiAnime **shut down 13 Mar 2026**. Any current "hianime"
domain is a copy, not the original team. Don't wire new code to aniwatch.to.

## anime-api (animeapi.cjhauser.me) — endpoints
Fronts the aniwaves.ru catalogue. Confirmed by probing the live service:
- `/api/search?keyword=&page=` — paginated, `page` is **1-based**; response is
  `results.data[]` plus `results.totalPage`. ~25 rows/page; a broad keyword is
  deep ("a" -> 354 pages). `q=` is silently ignored.
- `/api/info?id=<full series id>` — the detail endpoint (e.g. `naruto-76396`).
  Returns `results.data` (synopsis at `animeInfo.Overview`, `Genre`, `Country`,
  `Premiered`, `Date aired`, `Status`, `Scores`, `Duration`, `Studios`,
  `Producers`, `animeInfo.tvInfo.{sub,dub,eps}`), `results.seasons[]` (each with
  `season`, `season_poster`, `isActive`), and `data.recommended_data[]`.
  `anime_id`/`data_id`/`series_id` are all ignored -> `data: null`.
- `/api/episodes/<seriesId>` — `results.episodes[]` + `totalEpisodes`.
- `/api/stream?id=<urlencoded ep id>` — ep ids look like `naruto-76396?ep=76396_1`.
  Server chosen by **name** via `?server=<serverName>`; the default server is not
  always downloadable (DatSaV is embed-only; Vidplay/MyCloud return a file).
- `/api/info` with no/unknown id answers `{data:null,seasons:[]}` (HTTP 200), so
  "no detail" is a null-data check, not an HTTP error.
- Every catalogue row (search, seasons, recommended) shares
  `{id, poster, title, japanese_title, tvInfo}`.

## browserformobile — crash root cause (fixed 1.12.5)
The "Obsidian quits unexpectedly" during downloads was **unbounded read-ahead in
`downloadSegmentsStreaming`** (`src/hls.ts`). Workers fetched with no regard for
the writer, so one slow/rate-limited segment let every worker buffer the rest of
the episode. Harness: one 3 s segment in a 200 MB playlist -> **200 MB peak**
(OOM restart on a phone); after bounding the window to the worker count -> 11 MB,
same wall time. Latent since before 1.10.5; 1.11.5's server-fallback change made
long downloads common and exposed it.

## browserformobile — build/harness recipe
- `npm install` then `npm run build` (`tsc --noEmit && esbuild`) and `npm run lint`
  both must be clean; the built `main.js` byte-for-byte matches the released
  asset (verified against 1.11.5), so a source change is a real change.
- Ad-hoc harnesses under `/tmp/bfmh`: bundle with the repo's
  `node_modules/.bin/esbuild ... --alias:obsidian=<stub>.ts`. `npx esbuild` hangs
  here, and `npx prettier`/`js-beautify` are not available.
- Node harnesses need a `window` shim (`globalThis.window = globalThis` plus
  setTimeout/clearTimeout/setInterval) because `hls.ts` uses `window.setTimeout`.
- For jsdom harnesses, create the DOM in a module (`setup.ts`) imported **first**
  — a stub's top-level code that calls `document.createElement` runs before the
  test's own jsdom setup otherwise. Install `jsdom` in the harness dir and bundle
  with `--external:jsdom`.
- The released `main.js`/`manifest.json`/`styles.css` are GitHub release assets
  (not committed); `main.js` is gitignored.

See `.openhands/memory/2026-10-23.md` for the full session log.
