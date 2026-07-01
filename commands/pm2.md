---
description: Analyze a project and generate PM2 service commands for detected frontend, backend, or database services.
name: pm2
metadata:
  origin: ECC
---

# PM2 Init

Auto-analyze project and generate PM2 service commands.

**Command**: `$ARGUMENTS`

---

## Workflow

1. Check PM2 (install via `npm install -g pm2` if missing)
2. Scan project to identify services (frontend/backend/database)
3. Generate `ecosystem.config.cjs` and start it

---

## Service Detection

| Type | Detection | Default Port |
|------|-----------|--------------|
| Vite | vite.config.* | 5173 |
| Next.js | next.config.* | 3000 |
| Nuxt | nuxt.config.* | 3000 |
| CRA | react-scripts in package.json | 3000 |
| Express/Node | server/backend/api directory + package.json | 3000 |
| FastAPI/Flask | requirements.txt / pyproject.toml | 8000 |
| Go | go.mod / main.go | 8080 |

**Port Detection Priority**: User specified > .env > config file > scripts args > default port

---

## ecosystem.config.cjs

```javascript
module.exports = {
  apps: [
    // Node.js (Vite/Next/Nuxt)
    {
      name: 'project-3000',
      cwd: './packages/web',
      script: 'node_modules/vite/bin/vite.js',
      args: '--port 3000',
      env: { NODE_ENV: 'development' }
    },
    // Python
    {
      name: 'project-8000',
      cwd: './backend',
      script: 'venv/bin/uvicorn',
      args: 'app.main:app --host 0.0.0.0 --port 8000 --reload',
      interpreter: 'none'
    }
  ]
}
```

**Framework script paths:**

| Framework | script | args |
|-----------|--------|------|
| Vite | `node_modules/vite/bin/vite.js` | `--port {port}` |
| Next.js | `node_modules/next/dist/bin/next` | `dev -p {port}` |
| Nuxt | `node_modules/nuxt/bin/nuxt.mjs` | `dev --port {port}` |
| Express | `src/index.js` or `server.js` | - |

---

## Execute

Based on `$ARGUMENTS`:

1. Scan project for services
2. Generate `ecosystem.config.cjs`
3. Run `pm2 start ecosystem.config.cjs`
4. Report the port/name table and the terminal commands below

---

## Terminal Commands

```bash
pm2 start ecosystem.config.cjs && pm2 save   # first time
pm2 start all / pm2 stop all / pm2 restart all
pm2 start {name} / pm2 stop {name} / pm2 restart {name}
pm2 logs / pm2 logs {name}
pm2 status / pm2 monit
pm2 resurrect                                # restore saved process list
```
