#!/bin/bash
python3 run.py > server.log 2>&1 &
SERVER_PID=$!
echo "Server started with PID $SERVER_PID"

# Wait for port 8001 to become available (max 15 seconds)
for i in {1..15}; do
  if curl -s http://127.0.0.1:8001/health > /dev/null; then
    echo "Server is up!"
    break
  fi
  sleep 1
done

echo "--- Health Check ---"
curl -s http://127.0.0.1:8001/health
echo -e "\n\n--- Latest Anime Check ---"
curl -s http://127.0.0.1:8001/anime/latest
echo -e "\n\n--- Stopping Server ---"
kill $SERVER_PID
# Also kill any child processes of the reloader
pkill -P $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null
echo "--- Server Logs ---"
cat server.log
