# Deprecated Protocol Files

These files contain the original structured communication protocol design.

## Why Deprecated

The full structured protocol (YAML message envelopes, buffer-based communication) proved to be:

1. **Overly complex** - LLMs don't reliably output strict YAML format
2. **Requires Codex approval** - Buffer operations need user confirmation in non-full-auto mode
3. **Not necessary** - Simple text + lightweight metadata suffix works better

## Replacement

See `../lightweight-metadata.md` for the current approach:
- Natural language responses (LLM-friendly)
- Optional YAML metadata block at the end
- Graceful fallback if metadata is missing

## Files

- `protocol-schema.yaml` - Full message envelope schema (task_card, result_report, etc.)
- `protocol-cheatsheet.yaml` - Quick reference for the protocol
