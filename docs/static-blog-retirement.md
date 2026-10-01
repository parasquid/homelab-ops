# Retire a blog with static redirects

Use this procedure after the full articles and their media have been published
at their new homes. Keep the redirect project separate from the destination
sites: a rule for `/` applies to every hostname serving that asset directory.

## Build the mapping

Create an explicit list of each old article path and its final HTTPS URL.
Preserve historical dates and slugs when possible. Check the destination's
title and canonical URL as well as its HTTP status; a successful response can
still be the wrong page.

Inventory media URLs from the old articles, including `srcset`, linked images,
and WordPress thumbnail variants. Match each original file to its preserved
copy using a checksum. Send a thumbnail URL to that original copy when the
resized file was not preserved. Keep duplicate-copy choices deterministic and
record which article's primary home was selected.

Generate an `_redirects` file with explicit `301` status codes. Cloudflare's
default is `302`. Its static redirect syntax matches paths, not source
hostnames or query strings. Decide whether legacy query URLs are required
before selecting this approach.

Provide a small `404.html` that links to the new archive. Let unknown paths
return a real 404 unless there is an approved destination for them. A blanket
homepage redirect makes missing articles hard to detect.

## Preview and cut over

Use an asset-only Cloudflare project. Omit runtime code and Worker-first
routing when the static rules can handle every approved redirect. Check the
current static asset limits and billing before publishing; script invocation
has different billing from asset delivery.

Build with the repository's pinned tools in a disk-backed directory. Set
`TMPDIR`, `TMP`, and `TEMP` there, and keep generated packages out of Git.
Inspect the packaged rules and 404 page before uploading.

Publish a preview without binding the old production hostname. Verify every
article and media rule over HTTP, checking both the initial 301 and the final
destination. Check the homepage, an unknown path, and redirect loops.

Save the exact existing DNS record and routing configuration privately before
cutover. Recheck them immediately before changing the hostname so a concurrent
change is not overwritten. Use only credentials approved for that account and
zone, with the write permissions needed for the selected operation. Prepare
the reverse operation before changing production routing.

After cutover, verify normal public URLs without relying solely on cache-busting
parameters. If old pages remain cached, diagnose the affected URLs and use a
targeted purge. Confirm all redirects and media destinations before stopping
the old application. Stop only its identified container; preserve its volumes,
shared databases, and shared tunnel services for recovery.

## Record and maintain

Commit the redirect source, mapping, and reproduction commands. Keep tokens,
DNS snapshots, deployment IDs, and site-specific verification results in
ignored local inventory and handoff files. Record the active publisher and
how to deploy later mapping changes.

When a destination URL changes, update its old redirect directly to the new
final URL to avoid chains. Retain the old hostname and redirect project for as
long as the links should remain useful.

References: [Cloudflare static redirects](https://developers.cloudflare.com/workers/static-assets/redirects/),
[static asset billing](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/),
and [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/).
