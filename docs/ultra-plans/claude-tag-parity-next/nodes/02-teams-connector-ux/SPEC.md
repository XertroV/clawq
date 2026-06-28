# SPEC: Teams-First Connector Room UX

## Responsibility

Make room-agent interaction feel native and inspectable in work channels, with
Teams as the primary production connector and Slack as the Claude Tag comparison
baseline. Generalize behavior through connector capability fallbacks wherever
possible.

## In Scope

- Durable room session/progress records with artifact/backlink references.
- Visible progress checklists/cards for Teams and Slack.
- Teams Adaptive Card controls for inspect/continue/cancel where supported.
- Bounded Teams context/history capture and delivery observability.
- Connector rendering/fallback tests over Slack, Teams, Discord/web-style
  fallbacks.

## Out of Scope

- New connector transports.
- Slack Enterprise Grid deep migration.
- General UI dashboard beyond connector messages and CLI inspection.

## Backlog Target

P15: Teams-First Room-Agent UX.
