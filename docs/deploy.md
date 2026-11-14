# Deploying

Production runs on Google Cloud: the API on Cloud Run, data in Firestore, photos in Cloud Storage, and the web app on Firebase Hosting. [infra/README.md](../infra/README.md) covers creating it with Terraform and connecting the release to it. This page covers what a release does, how to tell it worked, and how to undo one.

> **Not ready for real users yet.** Django's users and refresh-token blacklist are in SQLite on the instance, so accounts disappear whenever the instance stops, which happens when it scales to zero and when a release moves traffic to a new revision. Until the GCIP migration (ClickUp 86bb3eu64) fixes that, the API runs on one instance at most (`max_instances` in `infra/variables.tf`), because with two, a user would exist only on the one they signed up on, and every request the other one answered would be a 401 ("User not found"). Keep the repository variables unset, so the release deploys nothing, or treat production as a demo.
>
> It also means one account's data isn't safe from another. Firestore data belongs to a username, and once the instance that had `alice` is gone, anyone can sign up as `alice` on the next one and get the real alice's people, trips and profile. Tokens name the user by username rather than by SQLite id, so at least an old token can't resolve to a different user who got the same id on a later instance. Don't put data in production that matters to anyone.

## What a release does

`.github/workflows/release.yml` runs when the CI Pipeline passes on a push to `main`, and deploys the commit CI tested. Nothing happens until the repository variables from infra/README.md exist. Until then, the gate job's summary says so.

The API (`deploy-api`):

1. Builds the production image (`backend/Dockerfile`, target `production`) and runs `make prod-image` on that exact image: boot, behaviour checks and the Trivy scan. Then it pushes it to Artifact Registry, tagged with the commit.
2. Deploys `firestore.rules` and `firestore.indexes.json` (`firebase deploy --only firestore`), and waits until no index is still building, for up to 30 minutes. A query without its index fails in production only, since the emulator ignores indexes.
3. Records which revision is serving.
4. Deploys a new revision with **no traffic**, tagged `candidate`, so it's reachable only at `CANDIDATE_URL`.
5. Runs the smoke test (`smoke/smoke.py`) against the candidate. If it fails, the release stops there and users never see the revision.
6. Moves all traffic to the new revision.
7. Runs the smoke test against the live URL. If that fails, traffic goes back to the revision recorded in step 3, and the job fails.

The web app (`deploy-web`), only after the API succeeds:

1. Builds the Flutter web app with `API_BASE_URL` set to the API.
2. Deploys it to Firebase Hosting, and checks the site answers 200.

A manual run (Actions → Production Release Pipeline → Run workflow, on `main`) deploys `main` as it is, without waiting for CI. Use it only when CI itself is broken.

## Is production healthy?

`.github/workflows/smoke.yml` runs the smoke test against `SMOKE_BASE_URL` every hour, and on demand. When it fails, it opens an issue labelled `smoke-failure`, or comments on the open one, and the next pass closes it. Until GCIP, it signs up a throwaway account each time, because there's no account that survives an instance restart to sign in with. Afterwards, set `SMOKE_USERNAME` and `SMOKE_PASSWORD` as secrets and pass them in `smoke.yml`.

Locally, `SMOKE_BASE_URL=https://… python3 smoke/smoke.py` runs it against any deployment.

## Rolling back

The API: Cloud Run keeps old revisions, and traffic can go back to one in seconds, with no rebuild.

```sh
gcloud run revisions list --service "$SERVICE" --region "$REGION"
gcloud run services update-traffic "$SERVICE" --region "$REGION" --to-revisions REVISION=100
```

The next release moves traffic to its own revision again, so fix forward on `main` before that.

Firestore indexes and rules aren't rolled back with a revision. An index the old code doesn't use costs nothing, so leave it. If a rules change is the problem, revert it on `main`. The rules deny all client access, so reverting means going back to deny-all.

The web app: Firebase Hosting keeps previous releases. Roll back in the Firebase console (Hosting → release history → Rollback), or with `firebase hosting:clone SITE:PREVIOUS_VERSION SITE:live`.

## The first deploy

Some things can only be checked once there's a real project. Do these on the first deploy, and again whenever the infrastructure changes:

- [ ] The release's Firebase steps succeed with the deployer's roles (`infra/iam.tf`). If one is refused, the error names the missing permission. Add the role there, not by hand.
- [ ] Rate limits count real clients. Sign in wrongly 11 times in a minute from one machine and get a 429, then sign in from another network and don't. If both get 429, `DJANGO_NUM_PROXIES` doesn't match what Cloud Run's front end puts in `X-Forwarded-For` (`infra/locals.tf`).
- [ ] A photo uploaded on the web app shows after a reload (the bucket's CORS and public read), and its URL is `https://storage.googleapis.com/<project>-media/…`.
- [ ] `https://<bucket-url>/` (the bucket itself, no object) is refused. Nobody can list the photos.
- [ ] A request to the run.app URL over plain HTTP is redirected to HTTPS.
