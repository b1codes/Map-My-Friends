// The k6 load test: what one API instance does under a steady mix of what
// the app sends. Run it with `make load` (scripts/load.sh), which starts the
// stack it expects (docker-compose.perf.yml) and passes these settings.
//
// setup() signs up PERF_USERS accounts through the API and fills each with
// a realistic amount of data: people in the stub geocoder's cities, two
// contact logs each, and trips whose stops name people and airports. Then
// five scenarios run side by side for PERF_DURATION, each at a fixed rate of
// iterations, so a slow API shows up as latency and dropped iterations
// rather than as a lower request rate:
//
//   app_open     what the app loads on opening: profile, people, trips,
//                contact logs (the Pulse tab)
//   browse       a person, their logs, a trip, the legs
//   log_contact  log a contact, add a note, reload people (their recency)
//   plan_trip    nearest hubs, a route, save a trip, book it, delete it
//   sign_in      sign in (the password hash is the most CPU a request
//                spends) and refresh the token
//
// Rates are per second, scaled by PERF_RATE_SCALE. The thresholds at the
// bottom fail the run (k6 exits 99) on any failed request or check, on a
// dropped iteration (the instance couldn't keep up), or on a scenario's p95
// latency over its budget. docs/testing.md explains how the budgets were
// set and what to do when one fails.

import { check, fail, group } from 'k6';
import http from 'k6/http';
import exec from 'k6/execution';

const BASE = (__ENV.PERF_BASE_URL || 'http://api:8000/api/').replace(/\/?$/, '/');
const USERS = Number(__ENV.PERF_USERS || 20);
const PEOPLE_PER_USER = Number(__ENV.PERF_PEOPLE || 25);
const TRIPS_PER_USER = Number(__ENV.PERF_TRIPS || 4);
const DURATION = __ENV.PERF_DURATION || '3m';
const SCALE = Number(__ENV.PERF_RATE_SCALE || 1);
const OUT = __ENV.PERF_OUT || '/out';

// Cities docker/e2e-stubs geocodes. setup() looks up an airport near each,
// so trips name real hubs.
const CITIES = [
  ['London', 'UK', 51.5074, -0.1278],
  ['Paris', 'France', 48.8566, 2.3522],
  ['Berlin', 'Germany', 52.52, 13.405],
  ['Chicago', 'USA', 41.8781, -87.6298],
  ['Boston', 'USA', 42.3601, -71.0589],
  ['Toronto', 'Canada', 43.6532, -79.3832],
];

// Iterations per second, and p95 budgets in milliseconds. Measured on
// 2026-11-07 (Apple Silicon, 3 ms each way), p95 was 40-60 ms for every
// scenario but sign_in (about 320 ms: the password hash holds the one vCPU).
// The budgets leave room for slower CI runners, and are still under what a
// request costs once its round trips grow with the account again (25 people
// is 25 more round trips on the people list, about 175 ms).
const SCENARIOS = {
  app_open: { rate: 2, p95: 200 },
  browse: { rate: 3, p95: 150 },
  log_contact: { rate: 1, p95: 200 },
  plan_trip: { rate: 0.5, p95: 250 },
  sign_in: { rate: 0.2, p95: 1000 },
};

function scenario(name, { rate }) {
  // A rate below one per second is expressed per 10 seconds.
  const perTen = Math.round(rate * SCALE * 10);
  return {
    executor: 'constant-arrival-rate',
    exec: name,
    rate: perTen,
    timeUnit: '10s',
    duration: DURATION,
    preAllocatedVUs: Math.max(2, Math.ceil(rate * SCALE * 4)),
    maxVUs: Math.max(10, Math.ceil(rate * SCALE * 20)),
  };
}

export const options = {
  setupTimeout: '5m',
  scenarios: Object.fromEntries(
    Object.entries(SCENARIOS).map(([name, config]) => [name, scenario(name, config)]),
  ),
  thresholds: {
    http_req_failed: ['rate==0'],
    checks: ['rate==1'],
    dropped_iterations: ['count==0'],
    ...Object.fromEntries(
      Object.entries(SCENARIOS).map(([name, { p95 }]) => [
        `http_req_duration{scenario:${name}}`,
        [`p(95)<${p95}`],
      ]),
    ),
  },
  // The default trend stats plus p99, for the summary table.
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// --- Requests ---------------------------------------------------------------

function headers(token) {
  return {
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  };
}

// name groups requests whose URLs carry ids, so the summary has one row per
// route rather than per record.
function call(method, path, body, token, name, expected = 200) {
  const params = {
    ...headers(token),
    tags: { name: name || `${method} ${path}` },
    responseCallback: http.expectedStatuses(expected),
  };
  const payload = body === undefined ? null : JSON.stringify(body);
  const response = http.request(method, BASE + path, payload, params);
  check(response, { [`${name || path} answers ${expected}`]: (r) => r.status === expected });
  return response;
}

function json(response) {
  try {
    return response.json();
  } catch (_) {
    return null;
  }
}

function pick(list) {
  return list[Math.floor(Math.random() * list.length)];
}

function point(lng, lat) {
  return { type: 'Point', coordinates: [lng, lat] };
}

function tripStops(people, airports) {
  const offset = Math.floor(Math.random() * CITIES.length);
  return [0, 1, 2].map((order) => {
    const city = (offset + order) % CITIES.length;
    const [, , lat, lng] = CITIES[city];
    return {
      sequence_order: order,
      location: point(lng, lat),
      people: [people[(offset + order) % people.length]],
      airport: order === 1 ? airports[city] : null,
      station: null,
    };
  });
}

// --- Setup: accounts with data ----------------------------------------------

function seedUser(n, run, airports) {
  const username = `load-${run}-${n}`;
  // Random, because the API refuses a password that resembles the username.
  const password = `Pw!${Math.random().toString(36).slice(2)}${Math.random().toString(36).slice(2)}9Z`;
  const registered = call(
    'POST',
    'user/auth/register/',
    { username, email: `${username}@example.com`, password, password_confirm: password },
    null,
    'POST user/auth/register/',
    201,
  );
  if (registered.status !== 201) fail(`sign-up ${username}: ${registered.status} ${registered.body}`);
  const tokens = json(call('POST', 'user/auth/token/', { username, password }, null, 'POST user/auth/token/'));
  const token = tokens.access;

  const people = [];
  for (let i = 0; i < PEOPLE_PER_USER; i++) {
    const [city, country] = CITIES[i % CITIES.length];
    const response = call(
      'POST',
      'people/',
      { tag: i % 3 ? 'FRIEND' : 'FAMILY', first_name: `Friend ${i}`, last_name: username, city, country },
      token,
      'POST people/',
      201,
    );
    people.push(json(response).id);
  }
  const logs = [];
  people.forEach((person, i) => {
    for (const day of [3, 17]) {
      const response = call(
        'POST',
        'contact-logs/',
        { person, channel: 'CALL', contacted_at: `2026-10-${day}T1${i % 10}:00:00Z` },
        token,
        'POST contact-logs/',
        201,
      );
      logs.push(json(response).id);
    }
  });
  const trips = [];
  for (let i = 0; i < TRIPS_PER_USER; i++) {
    const response = call(
      'POST',
      'trips/',
      { name: `Trip ${i}`, date: '2026-12-01', stops: tripStops(people, airports), legs: [] },
      token,
      'POST trips/',
      201,
    );
    trips.push(json(response).id);
  }
  const legs = json(call('GET', 'trips/legs/', undefined, token, 'GET trips/legs/')).map((leg) => leg.id);
  return { username, password, token, people, logs, trips, legs };
}

export function setup() {
  const run = Date.now().toString(36);
  const first = seedUser(0, run, []);
  const airports = CITIES.map(([, , lat, lng]) => {
    const response = call(
      'GET',
      `airports/nearest/?lat=${lat}&lon=${lng}&count=1`,
      undefined,
      first.token,
      'GET airports/nearest/',
    );
    return json(response).features[0].id;
  });
  const users = [first];
  for (let n = 1; n < USERS; n++) users.push(seedUser(n, run, airports));
  return { users, airports };
}

function user(data) {
  return data.users[exec.scenario.iterationInTest % data.users.length];
}

// --- Scenarios --------------------------------------------------------------

export function app_open(data) {
  const { token } = user(data);
  group('app_open', () => {
    call('GET', 'user/profile/', undefined, token);
    call('GET', 'people/', undefined, token);
    call('GET', 'trips/', undefined, token);
    call('GET', 'contact-logs/', undefined, token);
  });
}

export function browse(data) {
  const u = user(data);
  group('browse', () => {
    const person = pick(u.people);
    call('GET', `people/${person}/`, undefined, u.token, 'GET people/{id}/');
    call('GET', `contact-logs/?person=${person}`, undefined, u.token, 'GET contact-logs/?person={id}');
    call('GET', `trips/${pick(u.trips)}/`, undefined, u.token, 'GET trips/{id}/');
    call('GET', 'trips/legs/', undefined, u.token);
  });
}

export function log_contact(data) {
  const u = user(data);
  group('log_contact', () => {
    const created = call(
      'POST',
      'contact-logs/',
      { person: pick(u.people), channel: pick(['CALL', 'VIDEO', 'MESSAGE']), contacted_at: new Date().toISOString() },
      u.token,
      'POST contact-logs/',
      201,
    );
    const log = json(created);
    if (log && log.id) {
      call('PATCH', `contact-logs/${log.id}/`, { note: 'Caught up' }, u.token, 'PATCH contact-logs/{id}/');
    }
    call('GET', 'people/', undefined, u.token);
  });
}

export function plan_trip(data) {
  const u = user(data);
  group('plan_trip', () => {
    const [, , lat, lng] = pick(CITIES);
    call('GET', `airports/nearest/?lat=${lat}&lon=${lng}&count=3`, undefined, u.token, 'GET airports/nearest/');
    call('GET', `stations/nearest/?lat=${lat}&lon=${lng}&count=3`, undefined, u.token, 'GET stations/nearest/');
    const stops = tripStops(u.people, data.airports);
    call(
      'POST',
      'trips/calculate_route/',
      { coordinates: stops.map((s) => s.location.coordinates) },
      u.token,
      'POST trips/calculate_route/',
    );
    const created = json(
      call('POST', 'trips/', { name: 'Weekend', date: '2026-12-12', stops, legs: [] }, u.token, 'POST trips/', 201),
    );
    if (created && created.id) {
      call('PATCH', `trips/${created.id}/`, { status: 'BOOKED' }, u.token, 'PATCH trips/{id}/');
      call('DELETE', `trips/${created.id}/`, undefined, u.token, 'DELETE trips/{id}/', 204);
    }
  });
}

export function sign_in(data) {
  const u = user(data);
  group('sign_in', () => {
    const tokens = json(
      call('POST', 'user/auth/token/', { username: u.username, password: u.password }, null, 'POST user/auth/token/'),
    );
    if (tokens && tokens.refresh) {
      call('POST', 'user/auth/token/refresh/', { refresh: tokens.refresh }, null, 'POST user/auth/token/refresh/');
    }
  });
}

// --- Summary ----------------------------------------------------------------

function ms(value) {
  return value === undefined ? '' : `${Math.round(value)}`;
}

export function handleSummary(data) {
  const rows = [];
  for (const [key, metric] of Object.entries(data.metrics)) {
    const match = key.match(/^http_req_duration\{scenario:(\w+)\}$/);
    if (!match) continue;
    const name = match[1];
    const v = metric.values;
    const failed = metric.thresholds && Object.values(metric.thresholds).some((t) => !t.ok);
    rows.push(
      `| ${name} | ${ms(v.med)} | ${ms(v['p(95)'])} | ${ms(v['p(99)'])} | ${ms(v.max)} | ${SCENARIOS[name].p95} | ${failed ? '❌' : '✅'} |`,
    );
  }
  const m = data.metrics;
  const reqs = m.http_reqs ? m.http_reqs.values : { count: 0, rate: 0 };
  const failedRate = m.http_req_failed ? m.http_req_failed.values.rate : 0;
  const dropped = m.dropped_iterations ? m.dropped_iterations.values.count : 0;
  const markdown = [
    '## Load test',
    '',
    `${reqs.count} requests at ${reqs.rate.toFixed(1)}/s, ${(failedRate * 100).toFixed(2)}% failed, ${dropped} iterations dropped.`,
    '',
    '| Scenario | median ms | p95 ms | p99 ms | max ms | p95 budget | |',
    '|---|---|---|---|---|---|---|',
    ...rows.sort(),
    '',
  ].join('\n');
  return {
    stdout: `${markdown}\n`,
    [`${OUT}/summary.md`]: markdown,
    [`${OUT}/summary.json`]: JSON.stringify(data, null, 2),
  };
}
