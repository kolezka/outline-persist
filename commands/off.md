---
name: off
description: Disable automatic Outline persistence without removing the plugin.
---

Toggle automatic persistence for outline-persist.

- Disable: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/persistence-state.sh off`
- Re-enable: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/persistence-state.sh on`
- Status: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/persistence-state.sh status`

When off, the SessionStart hook stops injecting the durable-memory rule and no
automatic writes happen. The plugin stays installed; the manual commands still
work. `OUTLINE_HOOK_OFF=1` in the environment also forces off.

Run the requested toggle and report the new status.
