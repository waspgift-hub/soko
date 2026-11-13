const fs = require('fs');
const path = 'server/src/modules/legacy-compat/feature-compat.js';
let content = fs.readFileSync(path, 'utf8');

// Simple replacements
content = content.replace(/db\.collection\('users'\)\.doc\(([^)]+)\)\.get\(\)/g, 'commerceStore.getDocument("users", $1)');
content = content.replace(/db\.collection\('transactions'\)\.doc\(([^)]+)\)\.get\(\)/g, 'commerceStore.getDocument("transactions", $1)');
content = content.replace(/db\.collection\('notifications'\)\.add\(([^)]+)\)/g, 'commerceStore.addDocument("notifications", $1)');
content = content.replace(/db\.collection\('users'\)\.doc\(([^)]+)\)\.update\(([^)]+)\)/g, 'commerceStore.updateDocument("users", $1, $2)');
content = content.replace(/db\.collection\('transactions'\)\.doc\(([^)]+)\)\.update\(([^)]+)\)/g, 'commerceStore.updateDocument("transactions", $1, $2)');
content = content.replace(/db\.collection\('transactions'\)\.doc\(([^)]+)\)\.set\(([^)]+),\s*\{\s*merge:\s*true\s*\}\)/g, 'commerceStore.updateDocument("transactions", $1, $2)');
content = content.replace(/db\.collection\('transactions'\)\.doc\(([^)]+)\)\.set\(([^)]+)\)/g, 'commerceStore.setDocument("transactions", $1, $2)');
content = content.replace(/db\.collection\('users'\)\.doc\(([^)]+)\)\.set\(([^)]+)\)/g, 'commerceStore.setDocument("users", $1, $2)');
content = content.replace(/db\.collection\('flash_sales'\)\.add\(([^)]+)\)/g, 'commerceStore.addDocument("flash_sales", $1)');
content = content.replace(/db\.collection\('flash_sales'\)\.doc\(([^)]+)\)\.delete\(\)/g, 'commerceStore.deleteDocument("flash_sales", $1)');

fs.writeFileSync(path, content);
console.log('Refactored feature-compat.js');
