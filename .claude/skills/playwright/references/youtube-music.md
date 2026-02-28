# YouTube Music — Navigation & Automation Notes

URL: https://music.youtube.com

## Scrolling

**The main content area does NOT respond to `mousewheel` or `window.scrollBy`.**

- The only scrollable element (detected via `getComputedStyle`) is the **left sidebar** (`DIV#items.scroller`, `ytmusic-guide-section`).
- `mousewheel <dy> <dx>` syntax: first arg is vertical delta, second is horizontal. Example: `mousewheel 1500 0` = scroll down 1500px.
- The unfiltered Library page (`/library`) DOES scroll with `mousewheel 1500 0` — use that for broad scraping.
- The filtered Playlists view (`/library/playlists`) is **broken** — it caps at ~26 items regardless of scrolling attempts.

## Key Pages

| Page | URL | Notes |
|------|-----|-------|
| Library (all) | `/library` | Scrollable with mousewheel; shows ~199 items sorted by recent activity |
| Library (playlists filtered) | `/library/playlists` | **Broken** — only shows ~26 items, won't load more |
| Playlist | `/playlist?list=<id>` | Full playlist view |

## Data Extraction

### All items on the unfiltered library page
```js
// Run after scrolling to load all items
() => [...document.querySelectorAll('ytmusic-two-row-item-renderer')].map(el => ({
  name: el.querySelector('.title')?.textContent?.trim(),
  url: el.querySelector('a.yt-simple-endpoint')?.href,
  meta: el.querySelector('.subtitle')?.textContent?.trim()
})).filter(p => p.url?.includes('playlist?list='))
```

### All playlist links (sidebar + main content)
```js
() => [...document.querySelectorAll('a[href*="playlist"]')]
  .filter(a => a.textContent.trim())
  .map(a => ({ name: a.textContent.trim(), url: a.href }))
```

### Sidebar scrolling (the sidebar IS scrollable)
```js
const sidebar = document.querySelector('#items.scroller');
sidebar.scrollBy(0, 300); // repeat with await + delay
```

## Element Selectors

| Element | Selector |
|---------|----------|
| Playlist/album card | `ytmusic-two-row-item-renderer` |
| Card title | `.title` within card |
| Card subtitle/meta | `.subtitle` within card |
| Sidebar playlist links | `a[href*="playlist"]` |
| Sidebar scroll container | `#items.scroller` |
| Sort dropdown | `button[aria-label*="Sort"]` or look for dropdown near top of content |

## Playlist Pages

Playlist pages (`/playlist?list=...`) **do** scroll correctly with `mousewheel 1500 0`.

Track selector: `ytmusic-responsive-list-item-renderer`

Extract tracks:
```js
() => JSON.stringify(
  [...document.querySelectorAll('ytmusic-responsive-list-item-renderer')].map(el => ({
    title: el.querySelector('.title')?.textContent?.trim(),
    artist: el.querySelector('.secondary-flex-columns yt-formatted-string')?.textContent?.trim(),
    album: el.querySelectorAll('.secondary-flex-columns yt-formatted-string')[1]?.textContent?.trim(),
    duration: el.querySelector('.fixed-columns yt-formatted-string')?.textContent?.trim()
  })).filter(t => t.title)
)
```

Pages lazy-load in batches of ~100. Scroll until count stabilizes before extracting.

## Auth State

Saved auth state location: `~/.playwright-auth/youtube-music.json`

Load in future sessions:
```bash
playwright-cli open -s=ytmusic
playwright-cli state-load ~/.playwright-auth/youtube-music.json -s=ytmusic
playwright-cli goto https://music.youtube.com -s=ytmusic
```

## Merging Duplicate Playlists (Safe Workflow)

Do NOT assume the duplicate is a pure subset of the original — it may contain tracks not in the original (e.g. from a Soundiiz import that pulled in extras).

Safe merge process:
1. Open the **duplicate** playlist
2. Open the playlist action menu (three-dot / kebab menu at the top)
3. Choose **"Save playlist to..."** → select the **original** playlist
4. When prompted, select **"Skip duplicates"** — this adds only unique tracks from the duplicate to the original
5. Delete the duplicate

This ensures no tracks are lost regardless of which copy has what.

### Automation JS Snippets (refs expire quickly — use eval instead)

**Header element**: `ytmusic-responsive-header-renderer` (not `ytmusic-detail-header-renderer`)

**Open playlist Action menu:**
```js
() => {
  const header = document.querySelector('ytmusic-responsive-header-renderer');
  const btn = header?.querySelector('button[aria-label="Action menu"]');
  if (btn) { btn.click(); return 'clicked'; }
  return 'not found';
}
```

**Click "Save to playlist" menu item:**
```js
() => {
  const saveItem = [...document.querySelectorAll('yt-formatted-string')]
    .find(el => el.textContent.trim() === 'Save to playlist');
  const link = saveItem?.closest('a');
  if (link) { link.click(); return 'clicked'; }
  return 'not found';
}
```

**Select a playlist in the Save dialog (match by name + track count):**
```js
() => {
  const btn = [...document.querySelectorAll('button')]
    .find(b => b.textContent.includes('Absurd') && b.textContent.includes('136'));
  if (btn) { btn.click(); return 'clicked'; }
  return 'not found';
}
```

**Click "Skip duplicates" when prompted:**
```js
() => {
  const btn = [...document.querySelectorAll('button')]
    .find(b => b.textContent.trim() === 'Skip duplicates');
  if (btn) { btn.click(); return 'clicked'; }
  return 'not found';
}
```

**Click "Delete playlist" from action menu:**
```js
() => {
  const item = [...document.querySelectorAll('yt-formatted-string')]
    .find(el => el.textContent.trim() === 'Delete playlist');
  const link = item?.closest('a');
  if (link) { link.click(); return 'clicked'; }
  return 'not found';
}
```

**Confirm deletion (in the dialog):**
```js
() => {
  const btn = [...document.querySelectorAll('button')]
    .find(b => b.textContent.trim() === 'Delete');
  if (btn) { btn.click(); return 'clicked'; }
  return 'not found';
}
```

After confirming Delete, the page redirects to `/library/playlists` — that's confirmation the deletion succeeded.

## Finding Hidden / Duplicate Playlists

The library filtered view is broken and won't show all playlists. However, **search surfaces every copy**, including duplicates that don't appear in the library view.

To find both copies of a duplicate playlist:
1. Use the search bar and type the playlist name
2. Both copies will appear in results
3. This works even for playlists that are completely invisible in `/library/playlists`

This is the most reliable way to navigate to a specific playlist by name when automation needs to open a particular copy.

## Known Issues

- **Filtered playlists view caps at ~26 items** — use the unfiltered `/library` page instead for scraping playlists.
- The unfiltered library only shows the ~50 most recently interacted playlists. Older/unused playlists only appear in the (broken) filtered A-Z view.
- No way currently found to get a complete playlist list without the filtered view working.

## Scroll Recipe for Unfiltered Library

```bash
playwright-cli open --headed -s=ytmusic
# user logs in
playwright-cli goto https://music.youtube.com/library -s=ytmusic
playwright-cli mousemove 700 400 -s=ytmusic

# Loop until stable:
playwright-cli mousewheel 1500 0 -s=ytmusic   # vertical scroll down
# check count: playwright-cli eval "() => document.querySelectorAll('ytmusic-two-row-item-renderer').length" -s=ytmusic
```
