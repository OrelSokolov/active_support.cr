# active_support.cr — порт ActiveSupport

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `ActiveSupport` — 1:1. Оценка переносимости: ~85% (отчёт:
`/home/oleg/egui.cr/plans/crails-api-research.md`).

## Цель

Ежедневный набор core_ext + утилиты так, чтобы Ruby-код работал без
правок. Под капотом — добавление методов в stdlib-типы Crystal
(разрешено) и макросы вместо `define_method`.

## API 1:1

### core_ext (P0)
- `Object`: `blank?, present?, presence, in?, presence_in, deep_dup, to_param`
- `NilClass`: `blank?, present?, try`
- `String`: `squish, truncate, truncate_bytes, at, from, to, first, last,
  starts_with?, ends_with?, exclude?, remove, indent, strip_heredoc` +
  весь Inflector (`pluralize, camelize, underscore, tableize, classify,
  humanize, titleize, parameterize, demodulize, foreign_key, ordinalize`)
- `Hash`: `symbolize_keys, deep_symbolize_keys, stringify_keys, except,
  slice, reverse_merge, with_defaults, deep_merge, deep_transform_keys,
  deep_transform_values, compact_blank, assert_valid_keys`
- `Array`: `in_groups_of, in_groups, split, extract!, to_sentence,
  second/third/fourth/fifth/second_to_last, wrap, excluding, including`
- `Enumerable`: `index_by, index_with, many?, exclude?, pluck, pick, sole,
  in_order_of, compact_blank`
- `Int/Numeric`: `seconds, minutes, hours, days, weeks, fortnights, months,
  years, bytes..exabytes, multiple_of?, in_milliseconds` (Duration-механика)
- `Date/Time`: полная дата-математика — `beginning/end_of_day|week|month|
  quarter|year, all_day/all_week/..., ago/since, advance, change,
  yesterday/tomorrow, next_week/prev_*, months_ago/..., next_occurring,
  past?/future?/today?, to_fs(:db/:short/:long/:iso8601)`
- `Time.zone` / `TimeWithZone`: `in_time_zone (String и TimeZone-объект),
  utc, localtime, formatted_offset, zone/time_zone`; TimeZone поверх
  `Time::Location`.
- Per-user timezone (Iteration 8): `Time.use_zone(zone, &)` — fiber-local
  override (реестр `Hash(Fiber, TimeZone)`) + ensure-восстановление;
  `Time.zone` = fiber-override || глобальный `@@zone`; `Time.current`
  (= `Time.zone.now` при установленной зоне, иначе `Time.local`);
  `TimeZone#now`; TimeWithZone-арифметика `+/- (Span|секунды|TWZ)`,
  `since/ago`, `<=>`/`==` по UTC-инстанту, `strftime` (зонные поля),
  `to_s`/`to_fs` (`:db` → UTC, `:default` → Ruby Time#to_s-стиль);
  `I18n.l/localize` принимают TimeWithZone (формат в зоне). Оракул:
  19 кейсов `tz_*` в `oracle/cases.rb` → `expected.yml` (сняты с
  activesupport 8.1.4), зеркало `spec/oracle_spec.cr`.

### Инфраструктура (P0–P1)
- `ActiveSupport::Concern`: `included do / class_methods do` (Crystal
  `included`-хук + макросы)
- `delegate :name, to: :user, prefix:, allow_nil:` / `delegate_missing_to`
  → макросы
- `mattr_accessor/cattr_accessor, class_attribute, thread_mattr_*` →
  макросы над `@@`/fiber-locals
- `ActiveSupport::Notifications`: `instrument/subscribe/publish`
- `ActiveSupport::Cache`: `MemoryStore, NullStore, FileStore`;
  `fetch(read/write/exist?/delete, expires_in:, race_condition_ttl:)`
- Cache-адаптеры Iteration 7 (за портом `CacheStore`, см. статус):
  `RedisCacheStore` (redis), `SolidCacheStore` (PG-таблица — аналог
  solid_cache 1.0.x); оба — опциональные require `adapters/*`
- I18n: `t(key, scope:, default:, count:)`, yml-локали, плюрализация,
  `l` (localize), `available_locales`, fallbacks
- `NumberHelper`: `number_to_currency/delimited/human_size/human/
  percentage/phone/rounded` (locale-данные)
- `MessageVerifier/MessageEncryptor` (signed/encrypted cookies),
  `SecureRandom.base58/base36`, `Digest::UUID`
- `CurrentAttributes` на fiber-locals; `TaggedLogging`;
  `ActiveSupport::Deprecation`; `BacktraceCleaner`
- `HashWithIndifferentAccess`-аппроксимация для params (см.
  action_pack.cr): ключ Symbol|String.

## Реализация на Crystal

- core_ext = reopening stdlib-типов (`struct Int` / `class String`) —
  добавление методов разрешено, переопределение существующих запрещено.
- Duration: `5.days` возвращает `ActiveSupport::Duration`, календарные
  `months/years` — переменная длина; арифметика через `Time#shift`.
- `to_fs(:db)` — свой реестр форматов (символ → proc).
- `Constantize`-костыли не портируем: вместо них compile-time registry
  в зависимых шардах.

## Фазы

- P0: blank/present/try, Duration + дата-математика, Inflector, Concern,
  delegate, Notifications, Cache::Memory, NumberHelper, to_fs.
- P1: I18n + yml, Cache::File, MessageVerifier/Encryptor, CurrentAttributes,
  TaggedLogging, BacktraceCleaner.
- P2: TimeZone/TimeWithZone полный, Deprecation, глубокие хэш-операции.

## Статус (Iteration 8 — per-user timezone; база Iteration 7)

- Per-user timezone готов (см. «API 1:1» выше). Известные отклонения:
  Duration в Crystal-порту — фиксированный `Time::Span`, поэтому
  `twz + 1.day` сдвигает ровно 24 ч (у Rails Duration календарный:
  через границу DST отличается); fiber-local реестр зон не чистится,
  если fiber умирает внутри `use_zone`-блока; `Time.zone` без
  fiber-override процесс-глобальный (как `Time.zone=` в Rails).

## Статус (Iteration 9 — опции cookies-крипто; фаза C CRails)

- `MessageVerifier.new(secret : String | Bytes, url_safe = false,
  digest : Symbol = :sha256, force_legacy_metadata_serializer = false)`:
  выбор HMAC-дайджеста (sha1 — wire signed cookies actionpack, дефолт гемa;
  sha256 — дефолт порта, обратная совместимость), секрет байтами
  (ключи KeyGenerator), запись legacy-конверта
  `{"_rails":{"message":strict_b64(json),"exp":..|null,"pur":..|null}}`
  (имя опции — как в гемe; это wire-формат signed/encrypted cookies
  actionpack 8.1 — verifier c NullSerializer не входит в
  ENVELOPE_SERIALIZERS и всегда пишет legacy-конверт, даже в приложении
  с `use_message_serializer_for_metadata`). Чтение обоих конвертов —
  как раньше.
- `MessageEncryptor` — та же опция `force_legacy_metadata_serializer`
  (legacy-конверт внутри шифротекста) + `Bool` в MetadataPayload
  (обоим классам). 319/319.

## Статус (Iteration 7 — сетевые кэш-сторы)

- Порт `CacheStore` (`module CacheStore`: lookup/store/remove/clear)
  включён в `abstract class Store` — 1:1 Rails-API остался на Store,
  адаптеры пишутся против порта.
- `src/adapters/redis_cache.cr` — `RedisCacheStore` (jgaskins/redis:
  SET/GET с EX, INCRBY-счётчики, namespace, FLUSHDB).
- `src/adapters/pg_cache.cr` — `SolidCacheStore`: таблица
  `solid_cache_entries(key, value, expires_at)` + атомарные SQL-счётчики
  + `delete_expired` (аналог прунинга solid_cache).
- Оракул: `oracle/cache_stores_cases.rb` → `cache_stores_expected.yml`,
  снят с настоящей ActiveSupport 8.1.4 RedisCacheStore + redis-server
  (10 кейсов). Зеркало `spec/cache_stores_spec.cr` + общий контракт
  порта `spec/cache_store_contract.cr` гоняют все 4 стора
  (memory/file/pg/redis). 43 кейса кэша, сюит 269/269.
- Задокументированное отклонение: Rails RedisCacheStore оборачивает
  значения кодером, поэтому INCR по `write`-записи даёт nil; наши сторы
  хранят сырые строки и считают integer-parsable записи (10 → 11).
- FileStore: формат времени с суб-секундной точностью (экспирация < 1с).

## Готово, когда

`2.days.ago`, `%w[a b].to_sentence`, `"post".pluralize`,
`hash.deep_merge(...)`, `concern`/`delegate` в моделях — работают
сниппетами из Rails-документации без изменений.

## Зависимости

stdlib (YAML, JSON, OpenSSL, Crypto); pg + redis (только опциональные
require `adapters/*`, Iteration 7).
