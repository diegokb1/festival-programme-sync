# Festival Programme Sync — Take-Home

**Role:** Senior Rails / Hotwire Developer · **Time box:** 4 hours
**Stack:** Rails 8, Hotwire, PostgreSQL, Sidekiq, Tailwind (all in Docker)

## Context

You're joining a team that maintains a film festival's public website. It's a
Rails monolith that also acts as the editorial CMS, and it pulls programming data
from an external festival-management system over an API.

That external system is the source of truth for films, venues and screenings. Our
database holds a local copy so the site renders fast and stays up under load.
Today that copy is refreshed by a nightly script a colleague wrote in a hurry, and
it's been causing problems.

**Your job is to replace it.**

## What we've given you

A working Rails 8 app with `Film`, `Venue` and `Screening` models, a mock external
API at `/mock_api` that behaves like the real one including its failure modes, an
existing `VenueSync` service and its tests, a screenings index with a filter form,
and seed data.

### Running it

Everything runs in Docker. One step:

```bash
docker compose up --build
```

That starts Postgres, Redis, the Rails web server, a Tailwind watcher and Sidekiq,
and creates/migrates/seeds the database on first boot.

- App: <http://localhost:3000>
- Sidekiq dashboard: <http://localhost:3000/sidekiq>
- Postgres is exposed on host port **5544** (non-standard, so it won't collide)

Handy commands (see the `Makefile`):

```bash
make console   # rails console inside the web container
make test      # run the RSpec suite
make sh        # a shell in the web container
```

## What we'd like you to build

1. **A programme sync.** Pull screenings from `GET /mock_api/screenings` into our
   database. It's paginated, returns nested film and venue data, and behaves like a
   real third-party API: sometimes slow, sometimes failing partway through, and its
   records change between runs.

   Running it twice must not create duplicates. Running it after upstream data
   changes must update the local copy. If the API fails partway, records already
   retrieved shouldn't be lost. It should run on a schedule as a background job, and
   we should be able to tell afterwards whether a run succeeded and what it did.

2. **A filtered screenings list.** The index at `/screenings` has a filter form that
   reloads the whole page. Make it update just the results. Filters are date, venue,
   and a text search across titles. Keep it server-rendered; we're a Hotwire shop and
   aren't looking for a client-side rendering layer.

3. **A short README.** Half a page. What you'd do differently with more time, anything
   in the existing code you'd change and why, and any assumptions you made.

## Testing the mock API

| Parameter      | Effect                                                                                                     |
| -------------- | ---------------------------------------------------------------------------------------------------------- |
| `?page=2`      | Pagination, 25 records per page                                                                            |
| `?generation=2`| The dataset after upstream changes. Screenings have moved venue, some are cancelled, a film has been retitled, two screenings are new. |
| `?fail_after=8`| Returns 8 records, then a 500                                                                              |
| `?slow=true`   | Six-second delay                                                                                           |

Sync `generation=1`, then `generation=2`, and check the database is right. Then try
`generation=1&fail_after=8` and check nothing was lost.

## What we care about

- **Correctness under failure, ahead of feature completeness.** If you run short, a
  sync that handles the edge cases and a filter that doesn't quite work beats the
  reverse.
- Tests are expected — at least for the sync and the models. Tests for the view
  layer aren't. We're looking at how you test, not just that you did, so write
  your own; the repo doesn't hand you a test plan.

## Submitting

A private git repo with your commits. Please don't squash.

## Decisions made

**Idempotency.** I match every film, venue and screening on its `external_id`
rather than on a human-readable field like title or name, using
`find_or_initialize_by(external_id: ...)` followed by an `update!`/`save!` of
the rest of the attributes. Titles and names can change upstream (a film gets
retitled, a venue gets renamed) while the `external_id` stays stable, so
matching on `external_id` is what makes running the sync twice — or after
upstream data has changed — update the existing row instead of creating a
second one. I found the shipped `VenueSync` doing the opposite (matching on
`name`), which is exactly the bug this would cause: a rename upstream would
silently create a duplicate venue rather than updating the original. I fixed
`VenueSync` to match the same way, and I have tests that run the sync twice,
and once against each generation of the mock dataset, asserting the record
count doesn't change and the existing row picks up the new title/name.

**Failure handling.** I treat two kinds of failure differently, because they
call for different responses. A page fetch that keeps failing (the upstream
API is down, or `fail_after` never lets a later page through) means there's
genuinely no more data to get, so I retry it a few times with backoff and
then let the whole run fail — there's nothing else useful to do. A bad
individual record (invalid nested film or venue data) is different: it says
nothing about the other 59 records in the payload, so I catch it where it
happens, log it, and keep going instead of aborting the rest of the run over
one row. Either way, every record I've already saved stays saved — each
film/venue/screening upsert commits in its own transaction as soon as it
succeeds, rather than the whole run being one all-or-nothing transaction, so
a failure on page 6 doesn't undo pages 1–5.

**The `SyncRun` model.** The brief asks for a way to tell afterwards whether
a run succeeded and what it did, and that's all this model is for — it isn't
used to run the sync, only to record what happened. Every call to
`ProgrammeSync` creates one row with a `started_at`/`finished_at`, a status
(`success`, `partial`, or `failed`), a JSON `stats` column with per-type
created/updated counts, and — if something went wrong — an error message or
a list of the specific records that were skipped. `partial` versus `failed`
is the same distinction as above: `partial` means the run finished but had
to skip some bad records, `failed` means the run itself was aborted. I also
emit one structured JSON log line per run (at `:info`, `:warn`, or `:error`
depending on the outcome) so this is visible without opening a Rails console
— a log-based alert can key off the `status` field or the log level with no
extra infrastructure.

**`VenueSync` doesn't use `SyncRun`.** It's inherited code, not part of the
sync I was asked to build, and it isn't called from anywhere in the
app — `ProgrammeSync` does its own film/venue upserting rather than
delegating to it. My goal there was narrowly to fix the bug I found (matching
on `name` instead of `external_id`) and stop one bad record from aborting
the rest of the batch, not to bring it up to the same observability standard
as `ProgrammeSync`. So it only gets a `Rails.logger.error` per skipped
record, not a `SyncRun` row. I'd either delete it or fold it into
`ProgrammeSync` properly given more time, rather than maintain two separate
upsert implementations.

**The existing `VenueSync` had three problems, not one.** It matched venues
on `name` instead of `external_id` (see Idempotency above) — a venue renamed
upstream would silently create a second row instead of updating the first,
which is exactly the kind of bug that turns into manual ID reconciliation
later. It also had no error handling at all, so one bad record in the batch
would abort every venue after it. And its one shipped test only covered
creating a venue that didn't exist yet — it never exercised a second run, so
it would have kept passing even with the `name`-matching bug in place; it
was testing that the happy path worked, not that the sync was correct. I
fixed the key, added the per-record `rescue` + `Rails.logger.error`, and
added a test that runs the sync twice with a renamed venue and asserts no
duplicate gets created — the one the original test suite was missing. I
didn't rewrite `VenueSync` quietly: each of these was a separate, deliberate
change, not a wholesale replacement.

**Turbo Frame over Turbo Stream, plus a debounced auto-submit for search.**
The filter form only needed to replace one region of the page based on a
GET request, which is exactly what a Turbo Frame is for — I wrapped the
results in `turbo_frame_tag "screenings"` and pointed the form at it with
`data: { turbo_frame: "screenings" }`, so Turbo swaps just that frame instead
of doing a full page visit. I considered a Turbo Stream instead, but a
Stream is the better tool when a response needs to patch several unrelated
parts of the page at once, usually after a mutation (POST/PATCH/DELETE) —
here there's one region to update in response to a plain GET, so a Frame is
the simpler, more idiomatic fit and I didn't see a reason to reach for the
heavier tool. I also added `turbo_action: "advance"` on both the form and
the frame so filtering still updates the URL, keeping filtered views
bookmarkable and the back button working, even though only the frame
repaints.

For the title search specifically, I didn't want the user to have to click
"Filter" after every keystroke, but I also didn't want to fire a request on
every single keystroke either. So I added a small Stimulus controller
(`debounced_search_controller.js`) on the form that resets a timer on
`input` and calls `form.requestSubmit()` once the user pauses typing for
300ms. It doesn't do any rendering itself — it only decides *when* to submit
the same form that was already wired up to the frame, so the filtering
itself is still entirely server-rendered. Date and venue stay on the
explicit "Filter" button, since auto-submitting on every date keystroke or
select change didn't seem worth the same treatment.

**Sidekiq and how I stopped runs from overlapping.** `ProgrammeSyncJob` is a
plain Sidekiq job (via `config.active_job.queue_adapter = :sidekiq`), and I
scheduled it with `sidekiq-cron` rather than a rake task or a
self-rescheduling job, so the interval lives in one readable
`config/schedule.yml` file and is visible/editable from the Sidekiq Web UI
that was already mounted at `/sidekiq`, instead of being buried as a
magic-number constant in the job. It runs hourly.

For overlap, I didn't reach for a `SyncRun.running.exists?` check, because
that has a race window: two workers could both check at the same moment,
both see nothing running, and both start syncing. Instead I used a Postgres
advisory lock (`pg_try_advisory_lock`/`pg_advisory_unlock`), which is atomic
at the database level — there's no window where two workers can both think
they got it. If a scheduled run fires while a previous one is still going
(a slow upstream response, say), the second one just logs that it's skipping
and returns immediately rather than piling up a second sync on top of the
first.

I also made the job retry-aware, but only for the failure it makes sense to
retry: `retry_on ProgrammeSync::Error` (the API being unreachable), with
exponential backoff, up to 5 attempts. A bad individual record isn't retried
at the job level, because after the partial-failure handling above it isn't
even a job failure anymore — it just shows up in that run's `SyncRun` as a
skipped record.


## What would I have done differently

- **Delete local records that no longer come back from the API.** Right now
  the sync only creates and updates — if a screening (or film, or venue)
  stops appearing in the upstream payload entirely, its local row just stays
  there forever. With more time I'd track which external_ids were seen in a
  given run and remove anything that wasn't, so the local copy reflects
  removals too, not just additions and edits.
- **Move from polling to event-driven updates for individual records.** An
  hourly full sync means a change can sit for up to an hour before it shows
  up locally, and every run re-fetches and re-upserts the entire programme
  even when almost nothing changed. If the upstream system could push a
  webhook or callback on a single record changing — a screening's time
  moving, say — I'd update just that row immediately instead of waiting for
  the next scheduled full sync. The hourly sync would still be worth keeping
  as a safety net to catch anything a missed webhook let slip through, but it
  wouldn't be the only way changes get in.
- **Default the screenings list to only future screenings.** Right now
  `/screenings` shows every screening regardless of `starts_at`, past or
  future. For a festival programme that's not what a visitor actually wants
  by default — I'd filter to upcoming screenings unless a date filter says
  otherwise.
