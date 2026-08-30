require "socket"

host = Socket.gethostname

every "10s", as: "ticker" do
  puts "[#{host}] Tick: #{Time.now}"
end

cron "* * * * *", as: "pulsar" do
  puts "[#{host}] Pulse: #{Time.now}"
end

# A slow job: useful for watching overlap/skip behavior across instances.
every "30s", as: "slowpoke" do
  puts "[#{host}] Slowpoke started: #{Time.now}"
  sleep 5
  puts "[#{host}] Slowpoke finished: #{Time.now}"
end
