[![Gem Version](https://badge.fury.io/rb/schked.svg)](https://badge.fury.io/rb/schked)
[![Build Status](https://travis-ci.org/bibendi/schked.svg?branch=master)](https://travis-ci.org/bibendi/schked)

# Schked

Framework agnostic [Rufus-scheduler](https://github.com/jmettraux/rufus-scheduler) wrapper to run recurring jobs.

<a href="https://evilmartians.com/?utm_source=schked">
<img src="https://evilmartians.com/badges/sponsored-by-evil-martians.svg" alt="Sponsored by Evil Martians" width="236" height="54"></a>

## Installation

Add this line to your application's Gemfile:

```ruby
gem "schked"
```

And then execute:

```sh
bundle
```

Or install it yourself as:

```sh
gem install schked
```

## Usage

### Ruby on Rails

.schked

```
--require config/environment.rb
```

config/schedule.rb

```ruby
cron "*/30 * * * *", as: "CleanOrphanAttachmentsJob", timeout: "60s", overlap: false do
  CleanOrphanAttachmentsJob.perform_later
end
```

If you have a Rails engine with own schedule:

engine-path/lib/foo/engine.rb

```ruby
module Foo
  class Engine < ::Rails::Engine
    initializer "foo" do |app|
      Schked.config.paths << root.join("config", "schedule.rb")
    end
  end
end
```

And run Schked:

```sh
bundle exec schked start
```

To show schedule:

```sh
bundle exec schked show
```

### Duplicate scheduling

When you deploy your schedule to production, you want to start new instance before you shut down the current. And you don't want simultaneous working of both. To achieve a seamless transition, Schked is using Redis for locks.

You can configure Redis client as the following:

```ruby
Schked.config.redis_servers = ["redis://127.0.0.1:7777", "redis://127.0.0.1:7778", "redis://127.0.0.1:7779"]
```

### Callbacks

Also, you can define callbacks for errors handling:

config/initializers/schked.rb

```ruby
Schked.config.register_callback(:on_error) do |job, error|
  Raven.capture_exception(error) if defined?(Raven)
end
```

There are `:before_start`, `:after_finish` and `:around_job` callbacks as well.

Warning: `:before_start` and `:after_finish` callbacks are executed in the scheduler thread, not in the work threads (the threads where the job execution really happens).

`:around_job` callback is executed in the job's thread.

```ruby
Schked.config.register_callback(:around_job) do |job, &block|
  ...
  block.call
  ...
end
```

### Logging

By default Schked writes logs into stdout. In Rails environment Schked is using application logger. You can change it like this:

config/initializers/schked.rb

```ruby
Schked.config.logger = Logger.new(Rails.root.join("log", "schked.log"))
```

### Monitoring

[Yabeda::Schked](https://github.com/yabeda-rb/yabeda-schked) - built-in metrics for monitoring Schked recurring jobs out of the box! Part of the [yabeda](https://github.com/yabeda-rb/yabeda) suite.

### Testing

```ruby
describe Schked do
  let(:worker) { described_class.worker.tap(&:pause) }

  around do |ex|
    Time.use_zone("UTC") { Timecop.travel(start_time, &ex) }
  end

  describe "CleanOrphanAttachmentsJob" do
    let(:start_time) { Time.zone.local(2008, 9, 1, 10, 42, 21) }
    let(:job) { worker.job("CleanOrphanAttachmentsJob") }

    specify do
      expect(job.next_time.to_local_time)
        .to eq Time.zone.local(2008, 9, 1, 11, 0, 0)
    end

    it "enqueues job" do
      expect { job.call(false) }
        .to have_enqueued_job(CleanOrphanAttachmentsJob)
    end
  end
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bibendi/schked. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Schked project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/schked/blob/master/CODE_OF_CONDUCT.md).
