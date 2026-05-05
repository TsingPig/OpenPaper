import os
import json
from pathlib import Path
import urllib.parse

PDF_DIR = "papers"
METADATA_FILE = "metadata.json"

def main():
    if not os.path.exists(METADATA_FILE):
        print("❌ metadata.json 不存在，无法修复")
        return

    # 读取旧 metadata
    with open(METADATA_FILE, "r", encoding="utf-8") as f:
        old_metadata = json.load(f)

    # 构建：文件名 → metadata 反查索引
    filename_to_meta = {}
    for key, info in old_metadata.items():
        filename = os.path.basename(key).lower()
        filename_to_meta.setdefault(filename, []).append((key, info))

    new_metadata = {}
    repaired = 0
    lost = 0

    # 扫描当前实际存在的 PDF
    for root, _, files in os.walk(PDF_DIR):
        for fname in files:
            if not fname.lower().endswith(".pdf"):
                continue

            filename_lower = fname.lower()
            abs_path = os.path.join(root, fname)
            rel_path = os.path.relpath(abs_path, PDF_DIR).replace("\\", "/")

            # 反向匹配 metadata（通过文件名）
            candidates = filename_to_meta.get(filename_lower)

            if not candidates:
                print(f"⚠ 新 PDF：未找到旧 metadata 项：{rel_path}")
                continue

            # 取第一项（通常不存在重复）
            _, info = candidates[0]

            quoted_rel_path = "/".join(urllib.parse.quote(p) for p in rel_path.split("/"))

            # 更新新 metadata
            new_metadata[rel_path.lower()] = {
                **info,
                "file_key": rel_path.lower(),
                "pdf": f"{PDF_DIR}/{quoted_rel_path}",             # 相对路径
                "pdf_local": f"{PDF_DIR}/{quoted_rel_path}",       # 使用相对路径
            }

            repaired += 1

    # 检查丢失的 metadata 项（旧路径找不到 PDF）
    for key in old_metadata:
        file_exists = any(key.endswith(os.path.basename(k)) for k in new_metadata)
        if not file_exists:
            print(f"❌ metadata 丢失匹配项（文件已被移动或删除）：{key}")
            lost += 1

    # 覆写 metadata.json
    with open(METADATA_FILE, "w", encoding="utf-8") as f:
        json.dump(new_metadata, f, indent=2, ensure_ascii=False)

    print("\n======================")
    print(f"🔧 修复完成：{repaired} 条")
    print(f"⚠ 未匹配到：{lost} 条")
    print("======================")

if __name__ == "__main__":
    main()
