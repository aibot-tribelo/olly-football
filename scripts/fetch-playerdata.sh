#!/bin/bash
# Fetch GPS data from PlayerData API and write to content YAML
# Requires: PLAYERDATA_EMAIL, PLAYERDATA_PASSWORD env vars
set -e

if [ -z "$PLAYERDATA_EMAIL" ] || [ -z "$PLAYERDATA_PASSWORD" ]; then
  echo "⚠️ PlayerData credentials not set, skipping GPS fetch"
  exit 0
fi

echo "🔑 Logging in to PlayerData..."

# Get CSRF token
curl -s -c /tmp/pd-cookies.txt 'https://app.playerdata.co.uk/api/auth/identities/sign_in' > /tmp/pd-login.html
CSRF=$(grep -o 'csrf-token.*content="[^"]*"' /tmp/pd-login.html | sed 's/.*content="//' | sed 's/"//')

if [ -z "$CSRF" ]; then
  echo "❌ Failed to get CSRF token"
  exit 0
fi

# Login
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -b /tmp/pd-cookies.txt -c /tmp/pd-cookies2.txt \
  -X POST 'https://app.playerdata.co.uk/api/auth/identities/sign_in' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "authenticity_token=${CSRF}" \
  --data-urlencode "identity[email]=${PLAYERDATA_EMAIL}" \
  --data-urlencode "identity[password]=${PLAYERDATA_PASSWORD}")

if [ "$HTTP_CODE" != "302" ]; then
  echo "❌ Login failed (HTTP $HTTP_CODE)"
  exit 0
fi

echo "✅ Logged in, fetching GPS data..."

# Fetch match participations
curl -s -b /tmp/pd-cookies2.txt 'https://app.playerdata.co.uk/api/graphql' \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ currentPerson { name matchSessionParticipations(limit: 50) { id matchSession { id startTime endTime } metricSet { totalDistanceM maxSpeedKph sprintEvents highIntensityEvents } } } }"}' \
  > /tmp/pd-response.json

# Parse and write YAML
python3 -c "
import json

with open('/tmp/pd-response.json') as f:
    data = json.load(f)

if 'errors' in data:
    print('❌ API error:', data['errors'])
    exit(0)

participations = data['data']['currentPerson']['matchSessionParticipations']
sessions = []
for p in participations:
    ms = p.get('metricSet')
    if not ms or ms['totalDistanceM'] == 0:
        continue
    sessions.append({
        'date': p['matchSession']['startTime'][:10],
        'distance_m': round(ms['totalDistanceM']),
        'max_speed_kph': round(ms['maxSpeedKph'], 1),
        'sprints': ms['sprintEvents'],
        'high_intensity': ms['highIntensityEvents'],
    })

sessions.sort(key=lambda s: s['date'], reverse=True)

with open('src/content/gps/gps.yaml', 'w') as f:
    f.write('sessions:\n')
    for s in sessions:
        f.write(f'  - date: \"{s[\"date\"]}\"\n')
        f.write(f'    match: \"Bath City U18\"\n')
        f.write(f'    distance_m: {s[\"distance_m\"]}\n')
        f.write(f'    max_speed_kph: {s[\"max_speed_kph\"]}\n')
        f.write(f'    sprints: {s[\"sprints\"]}\n')
        f.write(f'    high_intensity: {s[\"high_intensity\"]}\n')

print(f'✅ Wrote {len(sessions)} GPS sessions to gps.yaml')
"

# Cleanup
rm -f /tmp/pd-cookies.txt /tmp/pd-cookies2.txt /tmp/pd-login.html /tmp/pd-response.json
