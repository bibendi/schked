# Integrate with Rails

Why: Rails is the most common host for Schked, and the railtie handles schedule discovery, logger setup, and engine integration automatically.

When to use it: when running Schked inside a Rails application or a Rails engine.

Steps:
1. Add `gem "schked"` to the Gemfile and run `bundle install`.
2. Create `config/schedule.rb` in the application root with job definitions.
3. Create `.schked` in the project root so the CLI can load Rails:
   ```
   --require config/environment.rb
   ```
4. Start the scheduler:
   ```sh
   bundle exec schked start
   ```
5. To inspect the loaded schedule:
   ```sh
   bundle exec schked show
   ```
6. For a Rails engine with its own schedule, register the path in an initializer:
   ```ruby
   module Foo
     class Engine < ::Rails::Engine
       initializer "foo.schked" do |app|
         Schked.config.paths << root.join("config", "schedule.rb").to_s
       end
     end
   end
   ```

Common mistakes:
- Creating `.schked` without `--require config/environment.rb`. The CLI will not boot Rails and the railtie will not run.
- Adding engine paths after `Schked.worker` has already been referenced. The worker is memoized, so late path additions are ignored.
- Configuring `Schked.config.logger` manually when the Rails logger is desired. The railtie sets `Rails.logger` unless a logger was already configured.

See also:
- Boot order: `initialization.md#boot-order`
- Redis locking in production: `recipes/configure-redis-locking.md`
