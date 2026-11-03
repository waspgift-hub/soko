import sys

with open('server/src/services/commerce-store.js', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Find the range of lines that contain the broken block
start_line = -1
end_line = -1

for i, line in enumerate(lines):
    if '// Generic collection helpers' in line or '\\n// Generic collection helpers' in line:
        start_line = i
    if '  markWebhookStatus,' in line and start_line != -1:
        # This might be the end of the broken block
        # The broken block is one giant line in the file
        pass

# Since the broken block is likely a single line with escaped newlines:
# Let's just remove the line that contains "async function countDocuments" and is not the one we inserted at the top.

new_lines = []
inserted_count = 0
for line in lines:
    # The functions we inserted at the top are on separate lines.
    # The broken one is on a single line.
    if 'async function countDocuments' in line and '\n' not in line and '\\n' in line:
        continue # Skip the broken line
    new_lines.append(line)

# Now we fix the exports
# Find the last 'module.exports = {'
exp_idx = -1
for i in range(len(new_lines)-1, -1, -1):
    if 'module.exports = {' in new_lines[i]:
        exp_idx = i
        break

if exp_idx != -1:
    # we want to add countDocuments, listDocuments, sumField to the exports
    # find the closing '};'
    closing_idx = -1
    for i in range(exp_idx + 1, len(new_lines)):
        if '};' in new_lines[i]:
            closing_idx = i
            break
    
    if closing_idx != -1:
        # Insert before closing_idx
        new_lines.insert(closing_idx, '  countDocuments,\n')
        new_lines.insert(closing_idx + 1, '  listDocuments,\n')
        new_lines.insert(closing_idx + 2, '  sumField,\n')

with open('server/src/services/commerce-store.js', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
