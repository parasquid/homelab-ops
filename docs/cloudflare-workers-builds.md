# Cloudflare Workers Builds for Hugo sites

This guide covers routine diagnosis and deployment checks for a Hugo site
connected to Cloudflare Workers Builds. Use the repository's own instructions
for its pinned tool versions, Wrangler configuration, production URL, and
deployment authorization. Record results for a real site only in its ignored
inventory and private handoff.

## Token scope and handling

Use the Cloudflare dashboard for ordinary build-log inspection when existing
read access is available. Open the Worker, select **Deployments**, choose
**View Build History**, and open the failed build.

For log retrieval through the Workers Builds API, Cloudflare documents the
`GET /accounts/{account_id}/builds/builds/{build_uuid}/logs` endpoint and lists
`Workers CI Read` as an accepted permission. Use read access only. The endpoint
also accepts `Workers CI Write`, but writing permission is not needed to read
logs. Cloudflare's Builds API guide describes user-scoped API tokens; follow
that token requirement when calling the API. The current Workers roles guide
maps the legacy `Workers CI Read` permission to `Content Read-Only`. Where the
token interface offers resource-level scope, restrict access to the Worker
being diagnosed. Cloudflare is migrating its permission model; if the token
interface only offers product-level scope, record that scope accurately rather
than describing it as Worker-specific.

Manual `wrangler deploy` of an existing Worker needs the Workers `Editor` role
for that Worker. If the deployment also changes a Route or Custom Domain, add
`Workers Routes Write` for each affected zone. Creating a Worker requires
product-level `Admin`; routine deployment of an existing Worker should not
need that broader role. Use a separate deployment credential from the
read-only log credential.

Store credentials in an approved protected secret store (for example,
Vaultwarden where configured) or protected environment. Do not put token
values in source files, chat, command history, process arguments, logs, or
tracked documentation. Keep any Cloudflare-managed build token distinct from
an API token used to read build logs or authenticate Wrangler. Do not copy
secret values from build logs into a handoff.

## Diagnose a failed GitHub check

1. Open the failed GitHub check and confirm the commit and branch it reports.
   If no Cloudflare build appears, check the repository connection, production
   branch setting, root directory, and build watch paths before retrying.
2. In Cloudflare, open the Worker, select **Deployments** and then **View Build
   History**. Open the matching build and inspect its build and deploy stages.
   If using the API, obtain the build UUID from the build details page and use
   the read-only log endpoint above. The API paginates logs with a cursor.
3. Compare the failure stage with the repository configuration:
   - For dependency or build failures, confirm the configured root directory,
     Hugo version, and build command. Workers Builds can use the `HUGO_VERSION`
     build variable; defaults can change, so pin a version when the repository
     requires a specific one.
   - For deploy failures, confirm that the Wrangler config is present in the
     configured root, its Worker name matches the existing Worker, and its
     assets settings point at the output produced by Hugo. If logs report a
     stale or rolled build token, select a valid build token in the Worker's
     Builds settings and retry.
   - For a missing build, confirm that the commit matches the configured
     branch and path filters and that the GitHub integration still has access.
   - For a timeout, check the duration of dependency installation and Hugo
     generation, then compare it with the current Workers Builds limits.
4. Check the local tool version with `hugo version`, then reproduce the
   production build with the version required by the repository. A common Hugo
   command is `hugo --minify`; treat it as an example and follow the site's
   documented command if it differs.
5. Retry from the Cloudflare build history only after fixing the cause. A
   successful build status confirms the build job completed; it does not prove
   that the intended public pages and assets are correct.

## Authorized manual deployment

Use a manual production deploy only when the requested work authorizes
publishing and the normal Workers Builds path is unavailable or cannot deploy
the verified change. First confirm the repository, branch, commit, Wrangler
configuration, and target Worker. Do not run Wrangler from an unknown
directory or allow automatic configuration to select an unreviewed target.

For a Hugo project whose Wrangler configuration serves its generated output,
the typical command split is:

```text
Build command:  hugo --minify
Deploy command: npx wrangler deploy
```

Use the Wrangler version locked by the repository. Run the build and deploy
from the configured project root with the approved credential already
available through the protected environment. Review the command target and
deployment result before treating the publish as complete.

## Verify the live site

After either a Workers Builds deployment or a manual deploy, inspect the actual
public result. Check the affected pages at their intended canonical HTTPS URLs,
including redirects and the canonical link element in the rendered HTML.
Verify each changed image or other asset loads successfully and returns the
expected content type, then inspect the rendered image and dimensions. Confirm
the page content reflects the deployed change. Use the public response as
evidence; a passing GitHub check, successful build, or successful Wrangler
command alone is not live verification.

Record site-specific deployment identifiers, diagnosis, test results, and
verification outcome only in the ignored inventory and private handoff. Keep
tracked documentation as reusable procedure.

## Cloudflare references

- [Workers Builds overview](https://developers.cloudflare.com/workers/ci-cd/builds/)
- [Troubleshooting Workers Builds](https://developers.cloudflare.com/workers/ci-cd/builds/troubleshoot/)
- [Workers Builds build image and version overrides](https://developers.cloudflare.com/workers/ci-cd/builds/build-image/)
- [Workers Builds API reference](https://developers.cloudflare.com/workers/ci-cd/builds/api-reference/)
- [Get Workers build logs API](https://developers.cloudflare.com/api/resources/workers_builds/subresources/builds/subresources/logs/methods/get/)
- [Workers roles and permissions](https://developers.cloudflare.com/workers/authorization/workers/)
- [Wrangler deploy command](https://developers.cloudflare.com/workers/wrangler/commands/workers/)
