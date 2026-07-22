# MCP Server Registry

The registry for onboarding **MCP servers** to the Azure Logic Apps hosted MCP
server platform. You describe your server in one small `manifest.json` and open a
pull request; the manifest is the single source of truth for how your server is
identified and where its image comes from.

> **Status: being built incrementally.** This repository currently defines the
> **manifest contract** and the **pull-request validation** that runs on every
> submission. The build/host/catalog pipeline that turns a merged manifest into a
> deployable server is delivered separately and documented as it lands. This
> README describes what's in the repo today and will grow with each addition.

## Who can onboard today

V1 is limited to **first-party (Microsoft) MCP servers** — e.g. servers published
by Microsoft product teams such as Azure SQL / Data API Builder, Cosmos DB, and
Playwright. Every manifest PR is reviewed and approved by the Azure MCP Service
team before it merges. Broader partner and community publishing is planned for a
later release.

---

## Onboarding a server

```
  1. Add your manifest ──▶ 2. Open a PR ──▶ 3. Validation + team review ──▶ 4. Merge
```

1. **Add your server.** Copy [`servers/_template/manifest.json`](servers/_template/manifest.json)
   to `servers/<your-server-id>/manifest.json`, fill it in, and add a square icon
   (`icon.svg` or `icon.png`) in the same folder.
2. **Open a pull request.** Automated validation runs on your manifest (see
   [Validation](#validation) below).
3. **Team review.** The Azure MCP Service team reviews the PR — this review is the
   trust gate for V1.
4. **Merge.** Once approved and green, your manifest is merged into the registry.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full step-by-step, including the
fork and permissions details (you don't need write access to this repo).

---

## The manifest

A manifest tells the platform what your server is and where to get it. Minimal
example:

```jsonc
{
  "$schema": "../../schemas/manifest.schema.json",
  "id": "mcp-my-server",
  "name": "My MCP Server",
  "description": "One line about what your server does.",
  "icon": "icon.svg",
  "version": "1.0.0",
  "publisher": { "name": "Your Organization", "url": "https://github.com/your-org" },
  "links": {
    "documentation": "https://github.com/your-org/mcp-my-server#readme",
    "support": "https://github.com/your-org/mcp-my-server/issues"
  },
  "source": {
    "type": "container",
    "image": "ghcr.io/your-org/mcp-my-server@sha256:<digest>",
    "targetPort": 8080,
    "mcpServerRoute": "/mcp"
  },
  "capabilities": ["tools"],
  "tags": ["example"]
}
```

The full field reference — every field, pattern, and allowed value — is in
[`schemas/manifest.schema.json`](schemas/manifest.schema.json), and
[`servers/_template/manifest.json`](servers/_template/manifest.json) is a
ready-to-copy starting point.

### Where your server comes from

The `source` block declares your server one of three ways — pick whichever
already fits:

| `source.type` | You provide | Good when |
|---|---|---|
| **`container`** | A pre-built image pinned by digest (`name@sha256:…`) | You already publish an image (GHCR, Docker Hub, MCR, …). |
| **`github`** | A repo URL, a Dockerfile path, and a commit SHA | You'd rather the image be built from your source. |
| **`local`** | A Dockerfile committed alongside this manifest in your server folder | You have no published image or separate repo — a small build or wrapper lives here. |

Either way the source is pinned to an **exact, immutable version**: `container`
by digest, `github` by commit SHA, and `local` by the manifest's own commit —
the schema does not accept mutable tags or branches.

### HTTP or STDIO transport

The `source.transport` field declares how your server speaks MCP:

- **`http`** — your server serves Streamable HTTP directly; set the `targetPort`
  and `mcpServerRoute` it listens on.
- **`stdio`** — your server speaks STDIO; set the `command` that starts it. You
  don't add an HTTP layer yourself.

### Configuration & authentication

- **`configuration[]`** declares the environment variables your server accepts,
  each with a description. Mark sensitive values with `"isSecret": true`.
- **`authentication`** (optional) declares how your server authenticates to an
  upstream data source — a named connection string, managed identity, or both.

---

## Validation

Every pull request that touches a manifest, the schema, or the scripts runs
[`.github/workflows/validate-pr.yml`](.github/workflows/validate-pr.yml). It runs
on public inputs only (no credentials) and checks that each server:

- **matches the JSON Schema** ([`schemas/manifest.schema.json`](schemas/manifest.schema.json)),
  validated with PowerShell's built-in `Test-Json` (draft-07);
- has a **folder name equal to its `id`**;
- has the **icon file** it references, under 500 KB, and (for SVG) free of
  embedded scripts — no `<script>`, event handlers, or `javascript:` URIs.

You can run the same checks locally before opening a PR:

```powershell
./scripts/validate-manifest.ps1 -ServerId <your-server-id>
```

Requires [PowerShell 7.4+](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
— no other tools or dependencies needed.

---

## Getting help

- **Onboarding questions:** open an issue in this repository.
- **Issues with a specific server:** use that server's `links.support` URL.
