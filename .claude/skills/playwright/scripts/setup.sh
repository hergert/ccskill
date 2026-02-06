#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Playwright TS Setup ==="

# Check bun
if ! command -v bun &>/dev/null; then
    echo "Installing bun..."
    curl -fsSL https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
fi
echo "bun $(bun --version)"

# Install deps in skill directory
cd "$SKILL_DIR"
if [ ! -d "node_modules/playwright" ]; then
    echo "Installing playwright..."
    bun install --no-save 2>&1 | tail -3
fi

# Install chromium
echo "Installing Chromium..."
bunx playwright install chromium 2>&1 | tail -3
bunx playwright install-deps chromium 2>/dev/null || true

# Verify
echo "Verifying..."
bun -e "
import { chromium } from 'playwright';
const b = await chromium.launch({ headless: true });
const p = await b.newPage();
await p.setContent('<h1>OK</h1>');
const t = await p.locator('h1').textContent();
await b.close();
if (t === 'OK') console.log('✅ Playwright ready.');
else { console.log('❌ Verification failed'); process.exit(1); }
"
