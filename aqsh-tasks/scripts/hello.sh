#!/bin/bash
set -e
echo "Hello, $NAME!"
echo "Task ID: $AQSH_TASK_ID"
echo "Current time: $(date)"
sleep 2
echo "Done!"
cat > "$AQSH_RESULT_FILE" << EOF
{
  "greeted": "$NAME",
  "timestamp": "$(date -Iseconds)"
}
EOF
