# Contracts

What the Flutter app and the Django API promise each other, and what each relies on from third parties. Both test suites run against these files on every PR, so a change on one side that breaks the other fails CI before it ships.

This is consumer-driven contract testing in the Pact style, without Pact. Pact's Dart consumer library is unmaintained and needs a native FFI library, and a broker adds nothing when both sides live in this repo and change in the same PR.

## Layout

```
contracts/
  api/
    schema.json          strict JSON Schema for every response shape ($defs)
    fixtures.json        the shared world: user, geocoder answer, placeholder ids, provider states
    interactions/*.json  one file per request the app makes, named <area>.<action>
  external/<provider>/   third-party interactions (*.json) and their schemas (*.schema.json)
  config/auth0.json      the Auth0 tenant both sides must agree on
```

An interaction holds the exact request the app sends (`method`, `path`, `query`, `auth`, plus a `json` or `multipart` body) and the response it depends on (`status`, the `schema` name in `schema.json`, an `example`, and optional `expect` values keyed by JSON Pointer).

## Who checks what

| Check | Where | When |
| --- | --- | --- |
| The app sends exactly the contract request and parses the example correctly | `frontend/test/contracts/api_contract_test.dart` | every PR |
| The API answers each contract request with the contract status, schema and `expect` values, on the Firestore emulator | `backend/tests/contracts/test_api_provider.py` | every PR |
| No field the app sends is silently dropped by a serializer, unless listed in `ignored_request_fields` | `backend/tests/contracts/test_api_provider.py` | every PR |
| Examples match their schemas, and contract files are well formed | `backend/tests/contracts/test_contract_files.py` | every PR |
| The app's OSRM request and route parsing; the Auth0 tenant in `ApiConfig` | `frontend/test/contracts/external_contract_test.dart` | every PR |
| Django's Auth0 token checks and the `fetch_stations` Overpass client, fed the contract examples; Auth0 settings | `backend/tests/contracts/test_external_consumers.py` | every PR |
| The real Auth0, OSRM and Overpass still answer as the contracts say | `backend/tests/contracts/test_live_providers.py` (`CONTRACT_LIVE=1`) | nightly, `.github/workflows/contracts-live.yml` |

Both sides fail on an interaction nobody tests: the Flutter suite needs a driver for every file, and Django needs a provider state for every `provider_state`.

## Changing the API

1. Change the interaction file and, if the shape changed, `schema.json`, including the `example`. The schemas are strict on purpose: every property is required and nothing else is allowed, so adding a response field is a contract change too.
2. Run both sides:
   ```sh
   docker compose exec api python manage.py test tests.contracts
   cd frontend && fvm flutter test test/contracts
   ```
3. Update whichever side fails.

To add an interaction, add its file, a driver in `api_contract_test.dart`, and (if it has a body) its serializer in `REQUEST_SERIALIZERS` in `backend/tests/contracts/states.py`. Ids in requests and examples are placeholders from `fixtures.json`; the provider swaps them for the real ids its state created.

## Known gaps

A contract the code doesn't meet yet is listed in `KNOWN_GAPS` (Django) or `knownGaps` (Flutter), with its ClickUp task. It runs as an expected failure, so fixing the code fails the suite until the entry is removed.

## Live checks

`test_live_providers` requests each external interaction marked `"live": true` from the real service and validates the answer against the same schema the consumer tests use. A provider that's still returning 429 or 5xx after retries counts as an outage, not drift: the check is skipped and a warning shows on the workflow run. Interactions that need a signed-in user (Auth0 `userinfo`, the access token itself) are `"live": false` and say why in `live_note`.

Run it locally with:

```sh
docker compose run --rm --no-deps -e CONTRACT_LIVE=1 api python manage.py test tests.contracts.test_live_providers
```
