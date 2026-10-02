# Cloudflare Workers Builds for Hugo sites

This guide covers routine diagnosis and deployment checks for a Hugo site
connected to Cloudflare Workers Builds. Use the repository's own instructions
for its pinned tool versions, deployment configuration, production URL, and
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

Editing a build trigger or starting a new build through the Builds API requires
write access to Workers Builds. Grant `Workers CI Write` or its current
equivalent for that task, then remove unneeded access when the task is done.
Check the token with the user-token verification endpoint before using the
Builds API; an account token can be valid for other Cloudflare APIs yet be
rejected by Builds. Keep the token in a protected store throughout the call.

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

If a credential client's default cache is read-only, keep its protection intact.
Create a temporary owner-only cache on disk-backed storage, configure the
expected vault server, and let the approved helper authenticate normally.
For the Bitwarden CLI, select that directory through `BITWARDENCLI_APPDATA_DIR`.
Keep passwords and unlock material in the existing protected mechanism. Remove
the exact temporary cache when the operation ends, including failure paths.

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
     requires a specific one. A Hugo template error such as `function "hugo"
     not defined` can mean the build selected an older Hugo release. Compare
     the version printed in the build log with the repository's pinned version
     before changing the template.
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
5. If the build trigger pins an outdated Hugo release, set its `HUGO_VERSION`
   environment variable to the version required by the repository. Use the
   production trigger's environment-variable update endpoint or the dashboard,
   then read the trigger back to confirm the value. Preserve other variables
   and their secrecy settings. The build image documents the version syntax;
   use the `extended_` prefix when the site requires Hugo Extended.
6. Start a fresh build from the production trigger or Cloudflare build history
   only after fixing the cause. Check its build and deploy stages. A
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

## Migrate a static Hugo Worker to `cf`

Pin `cf` and its Vite dependencies in the repository lockfile, and commit the
reviewed `cloudflare.config.ts` and Vite configuration before using them in CI.
Use a supported Node release. Build Hugo first: `cf` packages the generated
static assets but does not run the site's Hugo command for you.

For a project whose `build:cloudflare` script runs `cf build`, configure:

```text
Build command:  npm ci && hugo --minify && npm run build:cloudflare
Deploy command: npx cf deploy --prebuilt --mode production
```

Pin the repository's required Hugo version through `HUGO_VERSION`, and set
`CLOUDFLARE_ACCOUNT_ID` explicitly. Keep the Cloudflare-managed build token in
the Builds configuration. A separate API credential used to edit the trigger
does not replace that build token.

Stage the change on a nonproduction branch first. To retain inactive-version
review, use `npx cf workers versions create --prebuilt --mode production` as
that branch's deploy command. A named `cf previews deploy` deployment uses a
separate preview build; omit production domains and endpoint settings from the
configuration when `isPreview` is true. Match the prebuilt deployment mode to
the mode recorded by the build.

Use `cf previews deploy` for that preview workflow; choosing a Vite mode named
`preview` alone does not enable the CLI's preview build context.

For a Worker that redirects aliases before serving Hugo assets, keep its
entrypoint and redirect logic. Declare the asset binding with
`worker.env.ASSETS: bindings.assets()` and retain `worker.assets.runWorkerFirst`
when the previous configuration ran the Worker before the asset service.
Otherwise an existing asset can bypass a redirect. Preserve the HTML and
missing-page handling settings, and verify alias requests with a path and
query as well as the homepage.

Give a separate redirect Worker its own project directory, package manifest,
lockfile, Vite configuration, and `cloudflare.config.ts`. Build and deploy from
that directory so its output cannot be confused with the main site's output.
Declare only its intended custom domain and preserve whether workers.dev and
version preview endpoints are enabled. Keep a manually deployed redirect on
its existing publishing path unless a separate CI connection is chosen.

Read endpoint settings from the live Worker as well as its source config.
Missing fields in an older config do not establish whether workers.dev or
version previews are enabled. Preserve the observed booleans in the production
cf config. A named preview also needs an enabled preview host; a successful
upload with empty URL arrays does not establish that its output is reachable.
Keep disabled endpoint settings intact. Verify the packaged runtime locally,
then confirm that the inactive-version build succeeded for the exact source
commit. Record its version ID when the build response or logs provide it. A local
runtime check establishes packaged behavior; it does not establish remote
deployment health, which must be checked on the canonical URLs after publishing.
An inactive-version build can succeed without a publicly accessible version URL.

Before changing the production trigger, compare the packaged assets with the
Hugo output, validate the production build with a prebuilt dry run, and verify
the exact candidate through the branch build and runtime checks. Use a live
preview when the Worker has an enabled review endpoint. Preserve
separate redirect Workers and their configuration until they are migrated and
verified independently. Record the previous active Worker version and trigger
commands in the ignored handoff so rollback covers both traffic and future
builds. Remove the main Wrangler configuration only with the corresponding
CI command change; an old trigger cannot deploy a repository that has removed
the configuration it needs.

If a candidate cannot be pushed, restore the prior branch publisher while the
remote still has the old configuration. Preserve the required Hugo version and
other build settings. A wildcard branch trigger affects every matching branch;
bring active branches forward to the new configuration before using that
publisher on them.

Check both production and nonproduction Hugo version settings; they can
differ. After the branch build creates an inactive version, confirm that the
active production deployment is unchanged. Switch the production trigger only
after reviewing the staged output, then verify that production serves
the intended source commit. If a build fails while fetching the repository
before any build command runs, diagnose that stage and retry the same full
commit rather than changing the rendering or deployment configuration.

If a local and CI render differ, locate every difference before accepting
parity. For an environment-dependent date format, check that the instant and
offset are equivalent and that the rest of the rendered document is identical.
Compare the final production response with the verified CI output as well.

For a theme that shuffles recommendations, validate the selected links and card
metadata against published source pages, and compare the rest of each document
exactly. Compare production with its own active version without removing those
randomized regions: both endpoints should serve the same rendered assets.

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
- [Cloudflare CLI CI and automation](https://developers.cloudflare.com/cf/ci/)
- [Cloudflare CLI project configuration](https://developers.cloudflare.com/cf/projects/cloudflare-config/)
- [Cloudflare Vite plugin static assets](https://developers.cloudflare.com/workers/vite-plugin/reference/static-assets/)
- [Preview hosts and endpoint settings](https://developers.cloudflare.com/workers/previews/custom-domains/)
