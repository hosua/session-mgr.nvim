.PHONY: test integration smoke fmt check

test:
	nvim --headless -u NONE -l tests/run.lua spec

# Runs against a throwaway XDG tree so a bug can never touch real user data.
integration:
	@tmp=$$(mktemp -d) && \
	  XDG_DATA_HOME=$$tmp/data XDG_STATE_HOME=$$tmp/state XDG_CACHE_HOME=$$tmp/cache \
	  nvim --headless -u NONE -l tests/run.lua integration; rc=$$?; rm -rf $$tmp; exit $$rc

smoke:
	@for t in tests/smoke/*.sh; do [ -e "$$t" ] || continue; [ "$$(basename $$t)" = lib.sh ] && continue; echo "== $$t"; bash "$$t" || exit 1; done

fmt:
	stylua .

check:
	stylua --check .
