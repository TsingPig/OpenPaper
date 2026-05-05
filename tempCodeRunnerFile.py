import os
import json
import urllib.parse
from datetime import datetime
from pathlib import Path

PDF_DIR = "papers"
METADATA_FILE = "metadata.json"
OUTPUT_HTML = "index.html"
TEMPLATE_HTML = "template.html"

os.makedirs(PDF_DIR, exist_ok=True)

# 加载或创建 metadata
if os.path.exists(METADATA_FILE):
    with open(METADATA_FILE, "r", encoding="utf-8") as f:
        metadata = json.load(f)
else:
    metadata = {}

# 扫描 PDF 文件
papers = []
pdf_files = []
for root, _, files in os.walk(PDF_DIR):
    for fname in files:
        if fname.lower().endswith(".pdf"):
            abs_path = os.path.join(root, fname)
            rel_path = os.path.relpath(abs_path, PDF_DIR)
            rel_path = rel_path.replace(os.sep, "/")
            pdf_files.append((rel_path, fname))

pdf_files.sort(key=lambda item: item[0].lower())
legacy_keys_to_remove = set()

for rel_path, fname in pdf_files:
    key = rel_path.lower()
    legacy_key = fname.lower()

    info = metadata.get(key) or metadata.get(legacy_key, {})
    if legacy_key in metadata and key != legacy_key:
        legacy_keys_to_remove.add(legacy_key)

    quoted_rel_path = "/".join(urllib.parse.quote(part) for part in rel_path.split("/"))

    abs_path = os.path.abspath(os.path.join(PDF_DIR, rel_path))
    paper = {
        "file_key": key,
        "title": info.get("title", os.path.splitext(fname)[0]),
        "authors": info.get("authors", "Unknown"),
        "year": info.get("year", str(datetime.now().year)),
        "venue": info.get("venue", ""),
        "tags": info.get("tags", ["unsorted"]),
        "pdf": f"{PDF_DIR}/{quoted_rel_path}",
        "pdf_local": Path(abs_path).as_uri(),
        "read": info.get("read", False),
        "bib": info.get("bib", ""),
        "notes": info.get("notes", "")
    }

    papers.append(paper)
    metadata[key] = paper  # 保存最新数据，键为相对路径

for legacy_key in legacy_keys_to_remove:
    metadata.pop(legacy_key, None)

# 保存 metadata.json
with open(METADATA_FILE, "w", encoding="utf-8") as f:
    json.dump(metadata, f, indent=2, ensure_ascii=False)

# 渲染 HTML
if not os.path.exists(TEMPLATE_HTML):
    raise FileNotFoundError(f"{TEMPLATE_HTML} 不存在")

with open(TEMPLATE_HTML, "r", encoding="utf-8") as f:
    html = f.read()

html = html.replace("const EMBEDDED_PAPERS = [];", f"const EMBEDDED_PAPERS = {json.dumps(papers, ensure_ascii=False)};")

with open(OUTPUT_HTML, "w", encoding="utf-8") as f:
    f.write(html)

print(f"✅ 成功生成 {OUTPUT_HTML}，共 {len(papers)} 篇论文")
