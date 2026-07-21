module.exports = {
  apps: [{
    name: 'soko-vibe-server',
    script: 'index.js',
    instances: 'max',
    exec_mode: 'cluster',
    max_memory_restart: '512M',
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    merge_logs: true,
    env: {
      NODE_ENV: 'production',
    },
  }],
};
