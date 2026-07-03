# Initialization

## Required configuration

1. Add the gem to the application's Gemfile:
   ```ruby
   gem "schked"
   ```
   and run `bundle install`.

2. Create a schedule file. By convention this is `config/schedule.rb` in Rails applications, but any path can be used.

3. Make sure the schedule file is listed in `Schked.config.paths` before the worker starts. In Rails this happens automatically via the railtie; otherwise add it manually:
   ```ruby
   Schked.config.paths << File.expand_path("config/schedule.rb")
   ```

## Environment-specific setup

### Production / staging

- Set `REDIS_URL` or configure Redis explicitly:
  ```ruby
  Schked.config.redis = {url: ENV.fetch("REDIS_URL")}
  ```
- Ensure `standalone` remains `false` (the default outside test environments) so the Redis distributed lock is active.
- Run the scheduler with the CLI:
  ```sh
  bundle exec schked start
  ```

### Development

- You can run standalone to avoid needing Redis:
  ```ruby
  Schked.config.standalone = true
  ```
- Or point it at a local Redis instance and run the same command as production.

### Test

- The gem defaults to `standalone = true` when `RAILS_ENV=test` or `RACK_ENV=test`.
- Pause the worker in specs so jobs do not fire on their own:
  ```ruby
  worker = Schked.worker.tap(&:pause)
  ```
- See `recipes/test-scheduled-jobs.md` for the full testing pattern.

### Rails

- Create `.schked` in the project root with the line:
  ```
  --require config/environment.rb
  ```
- The railtie automatically adds `config/schedule.rb` and sets `Schked.config.logger` to `Rails.logger`.
- Start with `bundle exec schked start`.

### Rails engines

- Add the engine schedule path from an initializer:
  ```ruby
  initializer "my_engine.schked" do |app|
    Schked.config.paths << root.join("config", "schedule.rb").to_s
  end
  ```
- Do this before the worker is first referenced.

## Boot order

1. Application code configures `Schked.config` (paths, Redis, logger, callbacks).
2. The CLI or application loads `schked`, which creates `Schked.worker` lazily.
3. The worker evaluates schedule files and starts the scheduler.
4. In non-standalone mode the Redis lock is acquired and the 10-second extension loop begins.
5. The process blocks on `wait` until it receives `TERM` or `INT`.

## Common mistakes

- Requiring `schked` before adding custom schedule paths. The railtie runs at load time, but custom paths added after `Schked.worker` is referenced are ignored because the worker is memoized.
- Running production without Redis or with `standalone = true`. Two deployed instances will then fire the same jobs independently.
- Writing blocking work inside `before_start` or `after_finish` callbacks. They run in the scheduler thread and can delay other jobs.
- Forgetting that schedule files are `instance_eval`ed inside rufus-scheduler. Any helper methods or constants you reference must be available in that context.
