const fs = require('fs');
const content = fs.readFileSync('src/services/mailer.js', 'utf8');
const start = content.indexOf('function wrapEmailHtml');
const end = content.indexOf('async function sendMail');
const glassTemplate = `function wrapEmailHtml(html) {
  return \`<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body { margin: 0; padding: 0; background: #0B0B0B; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
  .container { max-width: 600px; margin: 0 auto; padding: 32px 16px; }
  .glass-card { background: linear-gradient(135deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.05) 100%); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.15); border-radius: 24px; padding: 40px 32px; margin-bottom: 24px; position: relative; overflow: hidden; }
  .glass-card::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 1px; background: linear-gradient(90deg, transparent, rgba(255,255,255,0.3), transparent); }
  .liquid-bg { position: absolute; top: -50%; left: -50%; width: 200%; height: 200%; background: radial-gradient(circle at 30% 20%, rgba(31,143,78,0.15) 0%, transparent 50%), radial-gradient(circle at 70% 80%, rgba(31,143,78,0.1) 0%, transparent 50%); pointer-events: none; }
  .header { text-align: center; padding-bottom: 32px; border-bottom: 1px solid rgba(255,255,255,0.1); margin-bottom: 32px; position: relative; z-index: 1; }
  .logo-img { width: 72px; height: 72px; border-radius: 20px; margin-bottom: 16px; box-shadow: 0 8px 32px rgba(31,143,78,0.3); }
  .title { font-size: 24px; font-weight: 700; color: #FFFFFF; margin: 0 0 8px; letter-spacing: -0.3px; }
  .subtitle { font-size: 14px; color: rgba(255,255,255,0.6); margin: 0; letter-spacing: 0.5px; text-transform: uppercase; }
  .content { font-size: 15px; color: rgba(255,255,255,0.9); line-height: 1.7; position: relative; z-index: 1; }
  .content h2 { color: #FFFFFF; font-size: 20px; margin: 0 0 12px; }
  .content p { margin: 0 0 16px; }
  .content strong { color: #1F8F4E; }
  .button { display: inline-block; background: linear-gradient(135deg, #1F8F4E 0%, #2D6A4F 100%); color: #FFFFFF; padding: 16px 40px; border-radius: 28px; text-decoration: none; font-weight: 600; font-size: 15px; margin: 20px 0; box-shadow: 0 4px 20px rgba(31,143,78,0.4); }
  .divider { height: 1px; background: linear-gradient(90deg, transparent, rgba(255,255,255,0.2), transparent); margin: 32px 0; }
  .footer { text-align: center; padding-top: 24px; font-size: 12px; color: rgba(255,255,255,0.4); }
  .footer a { color: #1F8F4E; text-decoration: none; }
  .badge { display: inline-block; background: rgba(31,143,78,0.2); color: #1F8F4E; padding: 6px 16px; border-radius: 20px; font-size: 12px; font-weight: 600; margin-bottom: 16px; border: 1px solid rgba(31,143,78,0.3); }
  .glass-inner { background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); border-radius: 16px; padding: 20px; margin: 16px 0; }
</style>
</head>
<body>
<div class="container">
  <div class="glass-card">
    <div class="liquid-bg"></div>
    <div class="header">
      <img src="https://www.sokovibe.co.tz/assets/icon-512.png" width="72" height="72" alt="Soko Vibe" class="logo-img">
      <h1 class="title">Soko Vibe</h1>
      <p class="subtitle">Soko la mtandaoni - Tanzania</p>
    </div>
    <div class="content">
      \${html}
    </div>
    <div class="divider"></div>
    <div class="footer">
      <p>Soko Vibe &copy; 2026. Haki zote zimehifadhiwa.</p>
      <p>Barua pepe hii imetumwa kwa gift@sokovibe.co.tz.</p>
      <p><a href="https://www.sokovibe.co.tz">www.sokovibe.co.tz</a> &middot; <a href="mailto:support@sokovibe.co.tz">support@sokovibe.co.tz</a></p>
    </div>
  </div>
</div>
</body>
</html>\`;
}
`;
const result = content.substring(0, start) + glassTemplate + content.substring(end);
fs.writeFileSync('src/services/mailer.js', result);
console.log('Done');
