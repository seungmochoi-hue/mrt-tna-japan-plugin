#!/bin/bash
# MRT T&A Japan Plugin - 스킬 자동 동기화 스크립트
# 로컬 ~/.claude/skills/ 에서 변경된 스킬을 마켓플레이스 레포로 동기화하고 푸시

REPO_DIR="C:/Users/User/mrt-tna-japan-plugin"
LOCAL_SKILLS="C:/Users/User/.claude/skills"

cd "$REPO_DIR" || exit 1

# 로컬 스킬을 레포로 복사
for skill_dir in "$LOCAL_SKILLS"/*/; do
  skill_name=$(basename "$skill_dir")
  dest="$REPO_DIR/skills/$skill_name"

  if [ ! -d "$dest" ]; then
    echo "새 스킬 발견: $skill_name"
    mkdir -p "$dest"
  fi

  cp -u "$skill_dir/SKILL.md" "$dest/SKILL.md" 2>/dev/null

  # marketplace.json skills 배열에 없으면 추가
  if ! grep -q "\"./skills/$skill_name\"" "$REPO_DIR/.claude-plugin/marketplace.json"; then
    python3 -c "
import json, sys
with open('$REPO_DIR/.claude-plugin/marketplace.json', 'r') as f:
    d = json.load(f)
d['plugins'][0]['skills'].append('./skills/$skill_name')
with open('$REPO_DIR/.claude-plugin/marketplace.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
print('marketplace.json 업데이트: $skill_name 추가')
"
  fi
done

# 변경 사항이 있으면 커밋 & 푸시
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "feat: 스킬 동기화 $(date '+%Y-%m-%d %H:%M')"
  git push origin main
  echo "✅ GitHub 푸시 완료"
else
  echo "변경 사항 없음"
fi
