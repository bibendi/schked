require "net/http"

res = Net::HTTP.get_response(URI("http://127.0.0.1:8080/healthz"))
exit(0) if res.code == "200"
exit(1)
