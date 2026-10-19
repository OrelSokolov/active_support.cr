# active_support.cr

A Crystal port of Rails **ActiveSupport 8.1.4** — core extensions
(`blank?`, Duration, date math, Inflector, deep hash ops), Concern,
delegate, Notifications, cache stores, I18n, number helpers, message
verification/encryption and time zones. Namespace `ActiveSupport`
mirrors the original 1:1; the goal is that Ruby snippets from the Rails
docs work unchanged. Estimated parity ~85%. Core extensions are
implemented by reopening Crystal stdlib types (adding methods is allowed;
overriding existing ones is not) and by macros in place of
`define_method`.

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

## Installation

```yaml
dependencies:
  active_support_cr:
    github: OrelSokolov/active_support.cr
```

```sh
shards install
```

Requires Crystal >= 1.21.0. `pg` and `redis` are needed only for the
optional `adapters/*` cache stores.

## Usage

```crystal
require "active_support_cr"

2.days.ago
%w[a b c].to_sentence            # => "a, b, and c"
"post".pluralize                  # => "posts"
hash.deep_merge(other)
"42".present?                     # => true
Time.use_zone("Europe/Berlin") { Time.current }
```

### Ruby-compat aliases

Ruby's `attr_*` macros are aliased for Rails migrants (delegating to the
idiomatic Crystal `getter`/`setter`/`property`):

```crystal
class Entry
  attr_reader :body, :content_type        # Ruby symbol style
  attr_accessor hits : Int32 = 0          # typed declarations work too
end
```


## Feature comparison vs activesupport 8.1.4

### Core extensions

| Feature | Original (activesupport) | Port (active_support.cr) | Status |
|---|---|---|---|
| `Object`: `blank?, present?, presence, in?, presence_in, deep_dup, to_param` | ✅ | Same | ✅ |
| `NilClass`: `blank?, present?, try` | ✅ | Same | ✅ |
| `String`: `squish, truncate, truncate_bytes, at/from/to, first/last, starts_with?/ends_with?, exclude?, remove, indent, strip_heredoc` | ✅ | Same | ✅ |
| Inflector: `pluralize, camelize, underscore, tableize, classify, humanize, titleize, parameterize, demodulize, foreign_key, ordinalize` | ✅ | Same | ✅ |
| `Hash`: `symbolize_keys, deep_symbolize_keys, stringify_keys, except, slice, reverse_merge, with_defaults, deep_merge, deep_transform_keys/values, compact_blank, assert_valid_keys` | ✅ | Same | ✅ |
| `Array`: `in_groups_of, in_groups, split, extract!, to_sentence, second..fifth, second_to_last, wrap, excluding, including` | ✅ | Same | ✅ |
| `Enumerable`: `index_by, index_with, many?, exclude?, pluck, pick, sole, in_order_of, compact_blank` | ✅ | Same | ✅ |
| `Int/Numeric`: `seconds..years, bytes..exabytes, multiple_of?, in_milliseconds` (Duration mechanics) | ✅ | Duration is a fixed `Time::Span` (see deviations) | 🔶 |
| `Date/Time` math: `beginning/end_of_*`, `all_day/...`, `ago/since`, `advance`, `change`, `yesterday/tomorrow`, `next_week/prev_*`, `months_ago/...`, `next_occurring`, `past?/future?/today?`, `to_fs(:db/:short/:long/:iso8601)` | ✅ | Same | ✅ |
| `constantize` / `String#constantize` | ✅ | Not portable — dependent shards use compile-time registries | ❌ (equivalent: compile-time class registry) |

### Time zones

| Feature | Original | Port | Status |
|---|---|---|---|
| `Time.zone`, `TimeWithZone`, `in_time_zone`, `utc/localtime`, `formatted_offset` | ✅ | TimeZone built on `Time::Location`; TWZ arithmetic, `<=>`/`==` by UTC instant, zoned `strftime`, `to_fs` | ✅ |
| Per-user timezone: `Time.use_zone(zone, &)` | ✅ | Fiber-local override registry + ensure-restore | ✅ |
| `Time.current`, `TimeZone#now`, `I18n.l` with TWZ | ✅ | Same | ✅ |
| DST-aware calendar Duration arithmetic across TWZ | ✅ | Duration is a fixed span — `twz + 1.day` always shifts 24 h | ❌ (equivalent: shift via `Time#shift` calendar math) |

### Infrastructure

| Feature | Original | Port | Status |
|---|---|---|---|
| `ActiveSupport::Concern` (`included do` / `class_methods do`) | ✅ | Crystal `included` hook + macros | ✅ |
| `attr_reader / attr_writer / attr_accessor` | ✅ | Aliases over `getter/setter/property`; Ruby symbol args (`:foo`) and typed declarations accepted | ✅ |
| `delegate :x, to: :y, prefix:, allow_nil:` / `delegate_missing_to` | ✅ | Macros | ✅ |
| `mattr_accessor/cattr_accessor, class_attribute, thread_mattr_*` | ✅ | Macros over `@@`/fiber-locals | ✅ |
| `ActiveSupport::Notifications` (`instrument/subscribe/publish`) | ✅ | Same | ✅ |
| `ActiveSupport::Cache`: `MemoryStore, NullStore, FileStore`; `fetch/read/write/exist?/delete, expires_in:, race_condition_ttl:` | ✅ | Same Store API | ✅ |
| `RedisCacheStore` | ✅ | `adapters/redis_cache.cr` (SET/GET EX, INCRBY counters, namespace); stores raw strings — INCR on a `write`-stored integer succeeds (Rails wraps values in a coder and returns nil) | 🔶 |
| `SolidCache` (PG table) | separate gem | `adapters/pg_cache.cr`: `solid_cache_entries(key, value, expires_at)` + atomic SQL counters + `delete_expired` | 🔶 |
| I18n: `t(key, scope:, default:, count:)`, yml locales, pluralization, `l`, `available_locales`, fallbacks | ✅ | Same | ✅ |
| `NumberHelper` family | ✅ | Same (locale data) | ✅ |
| `MessageVerifier` / `MessageEncryptor` (signed/encrypted cookies) | ✅ | SHA1/SHA256 digests, KeyGenerator-derived keys, legacy `{"_rails":...}` envelope read/write (wire format of actionpack 8.1 cookies) | ✅ |
| `SecureRandom.base58/base36`, `Digest::UUID` | ✅ | Same | ✅ |
| `CurrentAttributes` | ✅ | Fiber-locals | ✅ |
| `TaggedLogging`, `Deprecation`, `BacktraceCleaner` | ✅ | Same | ✅ |
| `HashWithIndifferentAccess` | ✅ | Approximation used by params: Symbol\|String keys | 🔶 |

## Deviations & Crystal-specific notes

- Core extensions reopen stdlib types (`struct Int`, `class String`);
  overriding existing stdlib methods is forbidden, so those keep Crystal
  semantics.
- `Duration` is a fixed `Time::Span`: calendar `months/years` have
  variable length, and TWZ arithmetic does not cross DST boundaries the
  way Rails durations do.
- The fiber-local zone registry is not cleaned up if a fiber dies inside
  a `use_zone` block; `Time.zone` without a fiber override is
  process-global (like Rails' `Time.zone=`).
- FileStore writes timestamps with sub-second precision (expiry < 1 s).
- Cache stores keep raw string values (see RedisCacheStore row).

## Testing

```sh
crystal spec
```

Suite: 323/323. Oracle specs (`oracle/cases.rb` → `expected.yml`,
including 19 `tz_*` timezone cases) are recorded with the real
activesupport 8.1.4 and replayed unchanged; cache stores are additionally
verified against a real redis-server (`oracle/cache_stores_cases.rb`)
and a shared contract spec runs across all four stores.
