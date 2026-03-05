---
name: compress-large-files
description: Compress large files and directories in ~/Desktop/MAIN/kalvin/testcase_and_creds to save disk space. Gzips logcat .txt files, tarballs raw Firebase result folders, and reports space saved. Use when user asks to compress test results, clean up testcase_and_creds, or free up disk space.
tools: Bash
---

# Compress Large Files — testcase_and_creds

Target directory: `~/Desktop/MAIN/kalvin/testcase_and_creds/`

## What gets compressed

| Type | Pattern | Action |
|---|---|---|
| Logcat text files | `logcat_v*.txt`, `v*_logcat.txt`, `logcat_v*` (no ext) | `gzip` in place → `.gz` |
| Raw Firebase result folders | `20*_firebase*/`, `20*_*/` (dated dirs) | `tar czf <name>.tar.gz <dir> && rm -rf <dir>` |
| Screenshot PNGs | `*.png` (>1 MB) | `gzip` in place → `.png.gz` |

## What is NOT touched

- `service-account-key.json` — credentials, never compress or move
- `logcat_v*.gz` / `*.tar.gz` — already compressed
- The most recent logcat (latest by modification time) — keep it readable for active debugging

## Workflow

### Step 1 — Show current state
```bash
du -sh ~/Desktop/MAIN/kalvin/testcase_and_creds/test-results/* | sort -rh | head -20
du -sh ~/Desktop/MAIN/kalvin/testcase_and_creds/
```

### Step 2 — Compress logcat text files (skip most recent)
```bash
RESULTS="$HOME/Desktop/MAIN/kalvin/testcase_and_creds/test-results"

# Find all uncompressed logcats, skip the newest one
LOGCATS=$(find "$RESULTS" -maxdepth 1 \( -name "logcat_v*.txt" -o -name "*_logcat.txt" \) | sort)
NEWEST=$(echo "$LOGCATS" | tail -1)

for f in $LOGCATS; do
  if [ "$f" = "$NEWEST" ]; then
    echo "Skipping newest: $f"
    continue
  fi
  gzip "$f" && echo "Compressed: $f → $f.gz"
done

# Compress logcats without extension
for f in "$RESULTS"/logcat_v*; do
  [ -f "$f" ] && [[ "$f" != *.gz ]] && [[ "$f" != *.txt ]] && \
    gzip "$f" && echo "Compressed: $f → $f.gz"
done
```

### Step 3 — Tar raw Firebase result folders
```bash
RESULTS="$HOME/Desktop/MAIN/kalvin/testcase_and_creds/test-results"
cd "$RESULTS"

for dir in 20*; do
  [ -d "$dir" ] && \
    tar czf "${dir}.tar.gz" "$dir" && \
    rm -rf "$dir" && \
    echo "Archived: $dir → ${dir}.tar.gz"
done
```

### Step 4 — Compress large PNGs (>1MB, skip thumbnails)
```bash
RESULTS="$HOME/Desktop/MAIN/kalvin/testcase_and_creds/test-results"
find "$RESULTS" -maxdepth 1 -name "*.png" -size +1M -exec gzip {} \; -print
```

### Step 5 — Report savings
```bash
echo "=== After compression ==="
du -sh ~/Desktop/MAIN/kalvin/testcase_and_creds/test-results/
du -sh ~/Desktop/MAIN/kalvin/testcase_and_creds/
```

## Split large files for distribution (e.g. GitHub upload)

### Split into 99 MB chunks
```bash
split -b 99m app.apk app.part-
# Produces: app.part-aa, app.part-ab, app.part-ac ...
```

### Combine parts back
```bash
cat app.part-* > app_restored.apk
```

### Verify integrity
```bash
# Before splitting — generate checksum
shasum -a 256 app.apk > app.apk.sha256

# After combining — verify
shasum -a 256 -c app.apk.sha256
# Expected: app.apk: OK
```

### Verify APK is a valid ZIP
```bash
unzip -t app_restored.apk
# Should end with: No errors detected in compressed data
```

> **Note:** Never gzip `.apk` files — APKs are already ZIP-compressed; gzip makes them larger.
> Always store the `.sha256` alongside the parts for later verification.

---

## Decompressing when needed

```bash
# Single logcat
gunzip ~/Desktop/MAIN/kalvin/testcase_and_creds/test-results/logcat_v25.txt.gz

# Firebase result folder
cd ~/Desktop/MAIN/kalvin/testcase_and_creds/test-results
tar xzf 2026-02-27_firebase.tar.gz

# All logcats
gunzip ~/Desktop/MAIN/kalvin/testcase_and_creds/test-results/logcat_v*.gz
```

## Expected savings

Logcat `.txt` files compress ~80% with gzip (text with repeating patterns).
Firebase result folders (video, screenshots, XML) compress ~30-50%.
Total expected: **5-6 GB → ~1.5-2 GB**.
