$stdout.sync = true # line-buffered logs even without a TTY

require "schked"

Schked.config.paths << File.expand_path("schedule.rb", __dir__)

# Feature flags (env vars, all optional):
#
#   SCHKED_JOB_RUN_STORE = database | redis | off   (default: database)
#   SCHKED_DB_DRIVER     = activerecord | sequel    (default: activerecord)
#   SCHKED_DB_ENGINE     = postgres | mysql         (default: postgres)
#   SCHKED_MAX_SKEW      = <seconds>                (default: 60)
#
# The schked_job_runs table is created automatically on boot, so any
# combination just works. `dip.yml` in this directory ships ready-made
# combos (dip scheduler-mysql, dip scheduler-sequel, dip cluster, ...).

store = ENV.fetch("SCHKED_JOB_RUN_STORE", "database")
driver = ENV.fetch("SCHKED_DB_DRIVER", "activerecord")
engine = ENV.fetch("SCHKED_DB_ENGINE", "postgres")
Schked.config.max_skew = Integer(ENV.fetch("SCHKED_MAX_SKEW", "60"))

urls = {
  "postgres" => ENV.fetch("SCHKED_POSTGRES_URL", "postgres://schked:schked@127.0.0.1:5432/schked"),
  "mysql" => ENV.fetch("SCHKED_MYSQL_URL", "mysql2://schked:schked@127.0.0.1:3306/schked")
}

ddl = {
  "postgres" => [
    <<~SQL,
      CREATE TABLE IF NOT EXISTS schked_job_runs (
        id BIGSERIAL PRIMARY KEY,
        job_name TEXT NOT NULL,
        window_start BIGINT NOT NULL,
        run_at DOUBLE PRECISION NOT NULL,
        claimer TEXT NOT NULL,
        CONSTRAINT schked_job_runs_unique UNIQUE (job_name, window_start)
      )
    SQL
    <<~SQL
      CREATE INDEX IF NOT EXISTS schked_job_runs_window_start_idx
        ON schked_job_runs (window_start)
    SQL
  ],
  "mysql" => [
    <<~SQL
      CREATE TABLE IF NOT EXISTS schked_job_runs (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        job_name VARCHAR(255) NOT NULL,
        window_start BIGINT NOT NULL,
        run_at DOUBLE NOT NULL,
        claimer VARCHAR(255) NOT NULL,
        UNIQUE KEY schked_job_runs_unique (job_name, window_start),
        KEY schked_job_runs_window_start_idx (window_start)
      )
    SQL
  ]
}.freeze

case [store, driver, engine]
in ["off", _, _]
  # Plain single-instance scheduler without any coordination.
in ["redis", _, _]
  Schked.config.job_run_store = :redis
in ["database", "activerecord", engine] if ddl.key?(engine)
  require "active_record"
  ActiveRecord::Base.establish_connection(urls.fetch(engine))
  ddl.fetch(engine).each { |statement| ActiveRecord::Base.connection.execute(statement) }
  Schked.config.job_run_store = :database
in ["database", "sequel", engine] if ddl.key?(engine)
  require "sequel"
  db = Sequel.connect(urls.fetch(engine))
  ddl.fetch(engine).each { |statement| db.run(statement) }
  Schked.config.database_connection = db
  Schked.config.job_run_store = :database
else
  abort "Unknown dummy combo: store=#{store.inspect} driver=#{driver.inspect} engine=#{engine.inspect}"
end

Schked.config.logger.info(
  "Dummy scheduler: store=#{store} driver=#{driver} engine=#{engine} " \
  "max_skew=#{Schked.config.max_skew}s"
)
