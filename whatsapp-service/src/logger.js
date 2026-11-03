const fs = require('fs');
const path = require('path');
const config = require('./config');
const { maskPhone } = require('./phone');

let dirReady = false;

// JSON lines, one per attempt. The message body is not stored: only its length,
// so customer text never ends up in plain-text logs.
function logMessage({ to, ok, wamid = null, errorCode = null, bodyLength = 0, source }) {
  const entry = {
    ts: new Date().toISOString(),
    source,
    to: maskPhone(to),
    ok,
    wamid,
    errorCode,
    bodyLength,
  };
  const file = path.resolve(config.logFile);
  const write = async () => {
    if (!dirReady) {
      await fs.promises.mkdir(path.dirname(file), { recursive: true });
      dirReady = true;
    }
    await fs.promises.appendFile(file, `${JSON.stringify(entry)}\n`);
  };
  write().catch((err) => console.error('[log] write failed:', err.message));
  return entry;
}

module.exports = { logMessage };
