---
name: tauri-v2-patterns
description: "Tauri v2 desktop app patterns: IPC commands, capabilities/permissions model, state management, events, plugins, and tauri.conf.json. Covers v2 breaking changes from v1."
metadata:
  origin: kbg
  tathep_projects:
    - tathep-player
---

# Tauri v2 Patterns

## v2 Breaking Changes from v1

The biggest v2 change is **capabilities** replacing the v1 allowlist. Every API the frontend can use must be explicitly permitted in `src-tauri/capabilities/`:

```json
// src-tauri/capabilities/main.json
{
  "identifier": "main-capability",
  "description": "Permissions for the main window",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "fs:allow-read-text-file",
    "fs:allow-write-text-file",
    "fs:scope-app-local-data-recursive",
    "shell:allow-open",
    "dialog:allow-open",
    "dialog:allow-save"
  ]
}
```

If a frontend call fails with `not allowed`, the capability is missing — add it here.

## IPC Commands

### Rust side

```rust
// src-tauri/src/lib.rs

#[derive(serde::Serialize, serde::Deserialize)]
struct VideoInfo {
    duration: f64,
    width: u32,
    height: u32,
}

// Sync command
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}!", name)
}

// Async command (preferred for anything that blocks)
#[tauri::command]
async fn get_video_info(path: String) -> Result<VideoInfo, String> {
    let info = ffprobe(&path).map_err(|e| e.to_string())?;
    Ok(VideoInfo { duration: info.duration, width: info.width, height: info.height })
}

// Access app state
#[tauri::command]
async fn process_video(
    path: String,
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
) -> Result<String, String> {
    let queue = state.queue.lock().await;
    queue.enqueue(path).await.map_err(|e| e.to_string())
}

pub fn run() {
    tauri::Builder::default()
        .manage(AppState::new())
        .invoke_handler(tauri::generate_handler![greet, get_video_info, process_video])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### Frontend side

```typescript
import { invoke } from '@tauri-apps/api/core'

// Invoke command
const message = await invoke<string>('greet', { name: 'World' })

// With error handling
try {
  const info = await invoke<VideoInfo>('get_video_info', { path: '/videos/movie.mp4' })
  console.log(info.duration)
} catch (error: unknown) {
  // error is the Rust Err() string
  console.error('Command failed:', error)
}
```

## App State

Manage shared Rust state via `app.manage()`. State must be `Send + Sync`:

```rust
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Default)]
struct AppState {
    player_status: Arc<Mutex<PlayerStatus>>,
    config: Arc<Mutex<AppConfig>>,
}

// Access in command
#[tauri::command]
async fn pause(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut status = state.player_status.lock().await;
    *status = PlayerStatus::Paused;
    Ok(())
}
```

## Events — Push from Rust to Frontend

Use events for progress updates, background task results, or status changes:

```rust
// Emit from Rust (to all windows)
app.emit("video-progress", serde_json::json!({
    "percent": 42.5,
    "current_frame": 1024,
})).unwrap();

// Emit to specific window
app.get_webview_window("main")
   .unwrap()
   .emit("playback-state", PlayerState::Playing)
   .unwrap();
```

```typescript
// Listen in frontend
import { listen } from '@tauri-apps/api/event'

const unlisten = await listen<{ percent: number }>('video-progress', (event) => {
  setProgress(event.payload.percent)
})

// Always clean up listeners
onUnmount(() => unlisten())
```

## Plugins

Common official plugins:

```toml
# src-tauri/Cargo.toml
[dependencies]
tauri-plugin-fs = "2"
tauri-plugin-dialog = "2"
tauri-plugin-shell = "2"
tauri-plugin-http = "2"
tauri-plugin-sql = { version = "2", features = ["sqlite"] }
tauri-plugin-store = "2"   # persistent key-value storage
tauri-plugin-updater = "2"
```

```rust
// Register plugins in lib.rs
tauri::Builder::default()
    .plugin(tauri_plugin_fs::init())
    .plugin(tauri_plugin_dialog::init())
    .plugin(tauri_plugin_store::Builder::default().build())
```

```typescript
// Use plugins on frontend
import { open } from '@tauri-apps/plugin-dialog'
import { readTextFile, writeTextFile, BaseDirectory } from '@tauri-apps/plugin-fs'
import { Store } from '@tauri-apps/plugin-store'

const file = await open({ filters: [{ name: 'Video', extensions: ['mp4', 'mkv'] }] })
const content = await readTextFile('config.json', { baseDir: BaseDirectory.AppLocalData })

const store = await Store.load('settings.json')
await store.set('volume', 80)
await store.save()
```

## Window Management

```rust
// Create a new window from Rust
tauri::WebviewWindowBuilder::new(&app, "settings", tauri::WebviewUrl::App("settings.html".into()))
    .title("Settings")
    .inner_size(400.0, 600.0)
    .resizable(false)
    .build()?;
```

```typescript
// From frontend
import { Window } from '@tauri-apps/api/window'

const settingsWindow = new Window('settings')
await settingsWindow.show()
await settingsWindow.setFocus()
```

## tauri.conf.json Key Settings

```json
{
  "productName": "TathepPlayer",
  "version": "1.0.0",
  "identifier": "com.tathep.player",
  "app": {
    "windows": [{
      "label": "main",
      "title": "Tathep Player",
      "width": 1200,
      "height": 800,
      "minWidth": 800,
      "minHeight": 600,
      "decorations": false,
      "transparent": true
    }],
    "security": {
      "csp": "default-src 'self'; img-src 'self' asset: https://asset.localhost"
    }
  },
  "bundle": {
    "active": true,
    "targets": "all",
    "icon": ["icons/32x32.png", "icons/128x128.png", "icons/icon.icns", "icons/icon.ico"]
  }
}
```

## Dev Workflow

```bash
# Start dev server with hot reload
pnpm tauri dev

# Build production binary
pnpm tauri build

# Build for specific target
pnpm tauri build --target aarch64-apple-darwin

# Add a plugin
pnpm tauri add fs
pnpm tauri add store
```

## Common Pitfalls

- **Capability not added → silent failure** — frontend `invoke()` may silently fail or throw a generic error if the capability permission is missing. Add to `capabilities/*.json` first.
- **`#[tauri::command]` parameter naming** — Tauri converts camelCase frontend args to snake_case Rust params automatically. `{ myParam }` in JS → `my_param: T` in Rust.
- **`tauri::State<'_>` lifetime** — always include the `'_` lifetime. `tauri::State<AppState>` (without lifetime) is a type error.
- **Blocking in async commands** — never call `std::thread::sleep` or sync blocking IO in `async fn` commands. Use `tokio::time::sleep` and `tokio::fs` instead.
- **Event listener cleanup** — `listen()` returns an `UnlistenFn`. Always call it on component unmount or you'll accumulate listeners across hot reloads.
- **CSP blocks local assets** — add `asset: https://asset.localhost` to CSP for local file access via `convertFileSrc()`.
