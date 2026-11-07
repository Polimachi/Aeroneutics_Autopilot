import re

def update_file(path, replacements):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    orig = content
    for target, repl in replacements:
        content = content.replace(target, repl)
    if content != orig:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Updated {path}")
    else:
        print(f"No changes in {path}")

# 1. Update relative links across ALL markdown files
import glob
all_md = glob.glob('docs/**/*.md', recursive=True)
for p in all_md:
    with open(p, 'r', encoding='utf-8') as f:
        c = f.read()
    # Replace link targets
    new_c = c.replace('sas/SAS_PROGRAM_SPECIFICATION.md', 'fcp/FCP_PROGRAM_SPECIFICATION.md')
    new_c = new_c.replace('[SAS_PROGRAM_SPECIFICATION.md]', '[FCP_PROGRAM_SPECIFICATION.md]')
    new_c = new_c.replace('[SAS_PROGRAM_SPECIFICATION.md](', '[FCP_PROGRAM_SPECIFICATION.md](')
    if new_c != c:
        with open(p, 'w', encoding='utf-8') as f:
            f.write(new_c)
        print(f"Link updated in {p}")

print("Phase 1 links completed.")
