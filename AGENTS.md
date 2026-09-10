# Agent notes (vless-all-in-one)

## Scope
- Fat installer: `vless-server.sh` (table-driven, mozisen/surge style). Prefer porting named upstream hunks; do not redesign.
- Companion: `nft.sh`. Docs: `README.md` / `README_CN.md` (keep minimal).

## Version sync (CI blocking)
- `readonly VERSION="…"` in `vless-server.sh` must match:
  - `Current script version: **v…**` in `README.md`
  - `当前脚本版本：**v…**` in `README_CN.md`
- Workflow: `.github/workflows/shell-check.yml` (`bash -n` + `VERSION_SYNC`).

## v3.5.20 product notes (docs surface)
- **mieru:** TCP|UDP; exclusive `port` or `port_range`; Traffic Pattern Advanced default off (UI Off/Conservative/Custom → store `off`/`conservative`/`unlocked`); `mierus://`; no port→user ACL; runtime-only `trafficPattern` object (not in db.json).
- **SSH Tunnel:** system OpenSSH only; Match Group; key-only; client TCP `-N -L/-D/-R`; no shell/exec/TTY/SFTP; no native UDP; no `ssh://` URI; keys on disk `0600` via `authorized_keys_path` only (never raw keys in db.json); candidate → `sshd -t/-T` → reload → admin verify → commit else rollback.

## Do not
- Force-push / FF `main` from feature work unless explicitly ordered.
- Store SSH private/public key material in `db.json`.
