# Contributing

This repo is how MCP server authors onboard a server to the Azure Logic Apps
hosted MCP server platform. Contributing is a **single pull request** that adds
your server's `manifest.json` and icon — no infrastructure to run and no service
code to change.

## Who can contribute today

V1 is limited to **first-party (Microsoft) MCP servers** (e.g. Azure SQL / Data
API Builder, Cosmos DB, Playwright). Every manifest PR is reviewed and approved
by the **Azure MCP Service team** (`@microsoft/azure-mcp-service-devs`) before it
merges — that review is the trust gate. Partner and community onboarding will
open in a later release.

## You do not need write access to this repo

This is a public repo, so you contribute the standard **fork + pull request** way.
You do **not** need to be granted any permission on `microsoft/mcp-server-registry`
to propose a server — a GitHub account (with Microsoft org SSO) is enough. Only
the Azure MCP Service team has write access, which is what lets them approve and
merge your PR.

## Steps

1. **Fork** this repository.
2. **Add your server.** Copy [`servers/_template/manifest.json`](servers/_template/manifest.json)
   to `servers/<your-server-id>/manifest.json` and fill it in. Commit a square
   icon (`icon.svg` or `icon.png`) in the same folder.
   - `id` must equal the folder name, be lowercase, and be unique.
   - Pin your source to an exact version: an image **digest** (`name@sha256:…`)
     for a `container` source, a commit **SHA** for a `github` source, or — for a
     `local` source — a Dockerfile committed in your server folder (built from the
     manifest's own commit).
   - See [`schemas/manifest.schema.json`](schemas/manifest.schema.json) for the
     full field reference. (Worked example manifests will be added in a
     follow-up PR once the validation workflow is on `main`.)
3. **Validate locally** (optional but recommended):
   ```powershell
   ./scripts/validate-manifest.ps1 -ServerId <your-server-id>
   ```
   Requires [PowerShell 7.4+](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell).
   No other dependencies — schema validation uses the built-in `Test-Json` cmdlet.
4. **Open a pull request** against `main`. Automated checks
   ([`validate-pr.yml`](.github/workflows/validate-pr.yml)) run on public inputs
   only — no credentials — and verify:
   - the manifest matches the JSON Schema,
   - the folder name matches `id`,
   - the referenced icon exists, is under 500 KB, and (for SVG) contains no
     embedded scripts (`<script>`, event handlers, or `javascript:` URIs).
   > On your first PR, a maintainer may need to approve running the workflow —
   > a GitHub default for public repositories.
5. **Team review.** The Azure MCP Service team reviews your PR (first-time
   onboarding of a new server gets a one-time look at identity/ownership,
   licensing, and naming). Later version bumps are lightweight — checks only.
6. **Merge.** Once approved and green, your manifest is merged into the registry.
   Building and hosting the server image from a merged manifest is handled by a
   separate pipeline (delivered incrementally, documented as it lands).

## Updating an existing server

Everything is a small PR to your `servers/<id>/` folder — git history is your
changelog:

- **New version:** bump `version` and update the pinned digest/commit.
- **Breaking change:** publish under a new server id (e.g. `mcp-my-server-v2`)
  rather than bumping in place.

## Contributor License Agreement

This project welcomes contributions and suggestions. Contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. By onboarding a server, you grant us the rights to include the
server in the Logic Apps hosted MCP server platform, "Connector Namespace." For details, visit
https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Questions

Open an issue in this repository. For issues with a specific server already in
the registry, use that server's `links.support` URL.
