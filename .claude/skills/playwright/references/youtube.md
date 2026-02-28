# YouTube — Navigation & Automation Notes

URL: https://www.youtube.com

## Auth State

Saved auth state: `~/.playwright-auth/youtube.json`

Note: YouTube and YouTube Music share the same Google account. The `youtube-music.json` state also works for YouTube, but save separately for clarity.

Load in future sessions:
```bash
playwright-cli open -s=yt
playwright-cli state-load ~/.playwright-auth/youtube.json -s=yt
playwright-cli goto https://www.youtube.com -s=yt
```

## Liked Videos

URL: `https://www.youtube.com/playlist?list=LL`

- The page title includes the total count, e.g. `(1297) Liked videos - YouTube`
- Initial page load populates ~100 items
- Items are sorted newest-liked first

### Filter Tabs (All / Videos / Shorts)

Filter tabs are **client-side only** — the URL does not change when switching tabs. To exclude Shorts:

```js
// Click the "Videos" tab to filter out Shorts
() => {
  const tab = [...document.querySelectorAll('[role="tab"]')]
    .find(t => t.textContent.trim() === 'Videos');
  if (tab) { tab.click(); return 'clicked'; }
  return 'not found';
}
```

Check which tab is active:
```js
() => [...document.querySelectorAll('[role="tab"]')]
  .map(t => t.textContent.trim() + ':' + t.getAttribute('aria-selected'))
  .join(', ')
```

After clicking the Videos tab, re-query `ytd-playlist-video-renderer` — the count will drop to only non-Shorts.

### Scrolling to Load More

`window.scrollBy` and `mousewheel` do NOT work for lazy-loading. Use:

```js
// Loads ~100 more items each call
() => { document.documentElement.scrollTop = 99999; }
```

Repeat until count stabilizes:
```js
() => document.querySelectorAll('ytd-playlist-video-renderer').length
```

### Extracting Liked Videos

Item selector: `ytd-playlist-video-renderer`

```js
() => JSON.stringify(
  [...document.querySelectorAll('ytd-playlist-video-renderer')].map(el => ({
    title:    el.querySelector('#video-title')?.textContent?.trim(),
    url:      el.querySelector('#video-title')?.href?.split('&list=')[0],
    channel:  el.querySelector('#channel-name a, ytd-channel-name a')?.textContent?.trim(),
    views:    el.querySelectorAll('#video-info span')[0]?.textContent?.trim(),
    age:      el.querySelectorAll('#video-info span')[2]?.textContent?.trim(),
    duration: el.querySelector('ytd-thumbnail-overlay-time-status-renderer span')?.textContent?.trim()
  }))
)
```

**Note:** `age` is the video's upload date (e.g. "7 years ago"), **not** when you liked it. YouTube does not expose the liked-at timestamp in the UI.

### Full Recipe: Recently Liked Videos (Videos only, no Shorts)

```bash
playwright-cli open -s=yt
playwright-cli state-load ~/.playwright-auth/youtube.json -s=yt
playwright-cli goto "https://www.youtube.com/playlist?list=LL" -s=yt

# Click Videos filter to exclude Shorts
playwright-cli eval "() => { const t = [...document.querySelectorAll('[role=\"tab\"]')].find(t => t.textContent.trim() === 'Videos'); t?.click(); return t ? 'ok' : 'not found'; }" -s=yt

# Scroll to load more (repeat until count stabilizes)
playwright-cli eval "() => { document.documentElement.scrollTop = 99999; }" -s=yt
# check: playwright-cli eval "() => document.querySelectorAll('ytd-playlist-video-renderer').length" -s=yt

# Extract all loaded items
playwright-cli eval "() => JSON.stringify([...document.querySelectorAll('ytd-playlist-video-renderer')].map(el => ({ title: el.querySelector('#video-title')?.textContent?.trim(), url: el.querySelector('#video-title')?.href?.split('&list=')[0], channel: el.querySelector('#channel-name a, ytd-channel-name a')?.textContent?.trim(), views: el.querySelectorAll('#video-info span')[0]?.textContent?.trim(), age: el.querySelectorAll('#video-info span')[2]?.textContent?.trim(), duration: el.querySelector('ytd-thumbnail-overlay-time-status-renderer span')?.textContent?.trim() })))" -s=yt
```

## Element Selectors

| Element | Selector |
|---------|----------|
| Video item | `ytd-playlist-video-renderer` |
| Video title + URL | `#video-title` |
| Channel name | `#channel-name a` or `ytd-channel-name a` |
| View count + age | `#video-info span` (index 0 = views, index 2 = age) |
| Duration badge | `ytd-thumbnail-overlay-time-status-renderer span` |
| Filter tabs | `[role="tab"]` |

## Known Notes

- The URL `playlist?list=LL` requires auth — redirects to login if not authenticated
- Filter tabs do not change the URL; state is client-side only
- Liked-at timestamp is not available in the YouTube UI
- Scrolling: only `document.documentElement.scrollTop = 99999` triggers lazy-load; `mousewheel` and `window.scrollBy` do not work
