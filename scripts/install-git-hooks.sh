#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="${HXHX_HOOKS_INSTALL_ROOT:-$SCRIPT_ROOT}"
ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

if ! git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
	echo "[hooks:install] ERROR: Git repository not found at $ROOT_DIR" >&2
	exit 1
fi

HOOKS_DIR="$(git -C "$ROOT_DIR" rev-parse --git-path hooks)"
if [[ "$HOOKS_DIR" != /* ]]; then
	HOOKS_DIR="$ROOT_DIR/$HOOKS_DIR"
fi

SRC_PRE_COMMIT="$ROOT_DIR/scripts/hooks/pre-commit"
DEST_PRE_COMMIT="$HOOKS_DIR/pre-commit"
DEST_CHAINED_PRE_COMMIT="$HOOKS_DIR/pre-commit.old"
SRC_POST_CHECKOUT="$ROOT_DIR/scripts/hooks/post-checkout"
DEST_POST_CHECKOUT="$HOOKS_DIR/post-checkout"
DEST_BD_POST_CHECKOUT="$HOOKS_DIR/post-checkout.bd"
DEST_USER_POST_CHECKOUT="$HOOKS_DIR/post-checkout.user"
SRC_POST_COMMIT="$ROOT_DIR/scripts/hooks/post-commit"
DEST_POST_COMMIT="$HOOKS_DIR/post-commit"
DEST_USER_POST_COMMIT="$HOOKS_DIR/post-commit.user"

is_bd_chained_pre_commit() {
	local hook_path="$1"

	if [ ! -f "$hook_path" ]; then
		return 1
	fi

	grep -Eq "bd sync --flush-only|bd hook pre-commit|beads pre-commit hook" "$hook_path"
}

is_repo_post_checkout() {
	local hook_path="$1"

	if [ ! -f "$hook_path" ]; then
		return 1
	fi

	grep -Eq "^# (HXHX_BD_POST_CHECKOUT_FAST_PATH_V1|HXHX_POST_CHECKOUT_USER_ONLY_V1)$" "$hook_path"
}

is_bd_post_checkout() {
	local hook_path="$1"

	if [ ! -f "$hook_path" ]; then
		return 1
	fi

	grep -q "^# bd-shim v1$" "$hook_path"
}

is_repo_post_commit() {
	local hook_path="$1"

	if [ ! -f "$hook_path" ]; then
		return 1
	fi

	grep -Eq "^# (HXHX_BD_POST_COMMIT_STATE_V1|HXHX_POST_COMMIT_USER_ONLY_V1)$" "$hook_path"
}

preserve_user_post_checkout() {
	local hook_path="$1"

	if [ -f "$DEST_USER_POST_CHECKOUT" ] && ! cmp -s "$hook_path" "$DEST_USER_POST_CHECKOUT"; then
		echo "[hooks:install] ERROR: refusing to replace existing post-checkout.user" >&2
		echo "[hooks:install] Reconcile $hook_path and $DEST_USER_POST_CHECKOUT manually." >&2
		exit 1
	fi

	cp "$hook_path" "$DEST_USER_POST_CHECKOUT"
	chmod +x "$DEST_USER_POST_CHECKOUT"
	echo "[hooks:install] Preserved user post-checkout hook -> $DEST_USER_POST_CHECKOUT"
}

preserve_user_post_commit() {
	local hook_path="$1"

	if [ -f "$DEST_USER_POST_COMMIT" ] && ! cmp -s "$hook_path" "$DEST_USER_POST_COMMIT"; then
		echo "[hooks:install] ERROR: refusing to replace existing post-commit.user" >&2
		echo "[hooks:install] Reconcile $hook_path and $DEST_USER_POST_COMMIT manually." >&2
		exit 1
	fi

	cp "$hook_path" "$DEST_USER_POST_COMMIT"
	chmod +x "$DEST_USER_POST_COMMIT"
	echo "[hooks:install] Preserved user post-commit hook -> $DEST_USER_POST_COMMIT"
}

# Keep the exact obsolete shim as an inert archive, never as an active delegate.
retire_bd_post_checkout() {
	local hook_path="$1"
	local retired="$HOOKS_DIR/post-checkout.bd.retired"
	if [ -f "$retired" ] && ! cmp -s "$hook_path" "$retired"; then
		echo "[hooks:install] ERROR: refusing to replace a different retired Beads hook" >&2
		exit 1
	fi
	if [ ! -f "$retired" ]; then
		cp "$hook_path" "$retired"
	fi
	rm "$hook_path"
	echo "[hooks:install] Retired automatic Beads checkout import -> $retired"
}

mkdir -p "$HOOKS_DIR"

if is_bd_chained_pre_commit "$DEST_PRE_COMMIT"; then
	cp "$SRC_PRE_COMMIT" "$DEST_CHAINED_PRE_COMMIT"
	chmod +x "$DEST_CHAINED_PRE_COMMIT"
	echo "[hooks:install] Detected bd chained pre-commit wrapper."
	echo "[hooks:install] Installed repo pre-commit hook -> $DEST_CHAINED_PRE_COMMIT"
else
	cp "$SRC_PRE_COMMIT" "$DEST_PRE_COMMIT"
	chmod +x "$DEST_PRE_COMMIT"
	echo "[hooks:install] Installed pre-commit hook -> $DEST_PRE_COMMIT"
fi

if [ -f "$DEST_POST_CHECKOUT" ] && ! is_repo_post_checkout "$DEST_POST_CHECKOUT"; then
	if is_bd_post_checkout "$DEST_POST_CHECKOUT"; then
		retire_bd_post_checkout "$DEST_POST_CHECKOUT"
	else
		preserve_user_post_checkout "$DEST_POST_CHECKOUT"
	fi
fi

if is_bd_post_checkout "$DEST_BD_POST_CHECKOUT"; then
	retire_bd_post_checkout "$DEST_BD_POST_CHECKOUT"
fi

cp "$SRC_POST_CHECKOUT" "$DEST_POST_CHECKOUT"
chmod +x "$DEST_POST_CHECKOUT"
echo "[hooks:install] Installed user-only post-checkout hook -> $DEST_POST_CHECKOUT"

if [ -f "$DEST_POST_COMMIT" ] && ! is_repo_post_commit "$DEST_POST_COMMIT"; then
	preserve_user_post_commit "$DEST_POST_COMMIT"
fi

cp "$SRC_POST_COMMIT" "$DEST_POST_COMMIT"
chmod +x "$DEST_POST_COMMIT"
echo "[hooks:install] Installed user-only post-commit hook -> $DEST_POST_COMMIT"
