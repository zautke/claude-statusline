# Fable usage evidence

Checked 2026-09-20.

Fable usage is obtainable, but it is not part of Claude Code's status-line
stdin payload. Claude Code exposes plan-wide `five_hour` and `seven_day`
windows there. The model-scoped Fable quota comes from the OAuth usage
endpoint:

```text
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <Claude Code OAuth token>
anthropic-beta: oauth-2025-04-20
```

Observed response shape used by Claude Code status-line implementations:

```json
{
  "limits": [
    {
      "kind": "weekly_scoped",
      "percent": 73,
      "resets_at": "2026-09-27T00:00:00Z",
      "scope": {"model": {"display_name": "Fable 5"}}
    }
  ]
}
```

Evidence:

- [Anthropic: Claude Fable models on your plan](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan) documents model-specific weekly Fable limits and tracking.
- [hex/claude-sessions statusline research](https://github.com/hex/claude-sessions/blob/main/docs/statusline.md) documents the endpoint and `limits[].kind=weekly_scoped` model-scoped extraction.
- [d-mato/claude-usage-bar investigation](https://github.com/d-mato/claude-usage-bar/issues/2) records the Fable payload shape with `percent`, `resets_at`, and model scope.
- [victor-shammas/claude-usage-menubar](https://github.com/victor-shammas/claude-usage-menubar) polls the same endpoint for 5-hour, weekly, and model-scoped quotas.

Local probe reached endpoint but received HTTP 429 (`rate_limit_error`), so
the renderer must retain the last fresh cache and show `n/a` when no usable
Fable bucket is available. Parser accepts `percent`, `used_percentage`, and
`utilization`, including `Fable 5` display names.
