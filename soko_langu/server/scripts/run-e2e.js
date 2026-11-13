#!/usr/bin/env node
'use strict';

/**
 * `npm run test:e2e` — the live deployment suite, explicitly opted in.
 *
 * The suite itself stays hermetic-by-default so `npm test` cannot hit the
 * network. Running the dedicated script is the opt-in, so it turns E2E_LIVE on
 * here rather than making every caller remember a platform-specific env prefix.
 */

const { spawnSync } = require('child_process');

const result = spawnSync(process.execPath, ['--test', 'test/e2e.live.test.js'], {
  stdio: 'inherit',
  cwd: require('path').resolve(__dirname, '..'),
  env: { ...process.env, E2E_LIVE: '1' },
});

process.exit(result.status === null ? 1 : result.status);
