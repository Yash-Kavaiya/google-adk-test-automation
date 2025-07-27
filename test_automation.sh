#!/bin/bash

# Test Automation Script for Conversational Testing
# Usage: ./test_automation.sh <input_csv> <api_endpoint> [output_csv]

# Configuration
INPUT_CSV="${1:-test_conversations.csv}"
API_ENDPOINT="${2:-http://127.0.0.1:8000/run_sse}"
OUTPUT_CSV="${3:-test_results.csv}"
SESSION_STORE_DIR="./sessions"
LOG_FILE="automation.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "SUCCESS") echo -e "${GREEN}✓ $message${NC}" ;;
        "ERROR") echo -e "${RED}✗ $message${NC}" ;;
        "WARNING") echo -e "${YELLOW}⚠ $message${NC}" ;;
        "INFO") echo -e "${BLUE}ℹ $message${NC}" ;;
    esac
}

# Function to create session directory
create_session_dir() {
    if [ ! -d "$SESSION_STORE_DIR" ]; then
        mkdir -p "$SESSION_STORE_DIR"
        log "Created session directory: $SESSION_STORE_DIR"
    fi
}

# Function to initialize result CSV
init_result_csv() {
    echo "conversation_id,message_sequence,message_content,response_status,response_time_ms,response_body,session_id,timestamp,error_message" > "$OUTPUT_CSV"
    log "Initialized result CSV: $OUTPUT_CSV"
}

# Function to create ADK session
create_adk_session() {
    local user_id=$1
    
    # Create session via ADK API and extract session ID
    local session_response=$(curl -s -X POST "http://127.0.0.1:8000/apps/test/users/${user_id}/sessions")
    local actual_session_id=$(echo "$session_response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    echo "$actual_session_id"
}

# Function to test API endpoint
test_message() {
    local conversation_id=$1
    local message_sequence=$2
    local message_content=$3
    local session_id=$4
    local user_id=$5
    
    # Prepare session file
    local session_file="$SESSION_STORE_DIR/session_${session_id}.json"
    
    # Create local session file if it doesn't exist
    if [ ! -f "$session_file" ]; then
        echo '{"conversation_history": []}' > "$session_file"
    fi
    
    # Prepare request payload for ADK format
    local payload=$(cat <<EOF
{
    "appName": "test",
    "userId": "$user_id",
    "sessionId": "$session_id",
    "newMessage": {
        "role": "user",
        "parts": [{"text": "$message_content"}]
    }
}
EOF
)
    
    # Record start time
    local start_time=$(date +%s%3N)
    
    # Make API call
    local response=$(curl -s -w "HTTPSTATUS:%{http_code};TIME:%{time_total}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Session-ID: $session_id" \
        -d "$payload" \
        "$API_ENDPOINT" 2>/dev/null)
    
    # Calculate response time
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    # Extract HTTP status and response body
    local http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local time_total=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    local response_body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]*;TIME:[0-9.]*$//')
    
    # Handle empty response
    if [ -z "$http_status" ]; then
        http_status="000"
        response_body="Connection failed"
    fi
    
    # Determine if successful
    local error_message=""
    if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
        print_status "SUCCESS" "Conv $conversation_id, Msg $message_sequence: $http_status"
    else
        error_message="HTTP $http_status"
        print_status "ERROR" "Conv $conversation_id, Msg $message_sequence: $http_status"
    fi
    
    # Escape quotes in response body and message content for CSV
    local escaped_response=$(echo "$response_body" | sed 's/"/\\"/g')
    local escaped_message=$(echo "$message_content" | sed 's/"/\\"/g')
    local escaped_error=$(echo "$error_message" | sed 's/"/\\"/g')
    
    # Write to result CSV
    echo "$conversation_id,$message_sequence,\"$escaped_message\",$http_status,$response_time,\"$escaped_response\",$session_id,$(date '+%Y-%m-%d %H:%M:%S'),\"$escaped_error\"" >> "$OUTPUT_CSV"
    
    # Update session file with conversation history
    if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
        local updated_session=$(cat "$session_file" | jq --arg msg "$message_content" --arg resp "$response_body" '.conversation_history += [{"message": $msg, "response": $resp, "timestamp": now}]')
        echo "$updated_session" > "$session_file"
    fi
    
    log "Conversation $conversation_id, Message $message_sequence: Status $http_status, Time ${response_time}ms"
}

# Function to process CSV file
process_conversations() {
    local line_number=0
    local conversation_id=1
    
    # Read CSV file line by line, skipping header
    while IFS=',' read -r message1 message2 message3 message4 message5; do
        line_number=$((line_number + 1))
        
        # Skip header row
        if [ $line_number -eq 1 ]; then
            continue
        fi
        
        print_status "INFO" "Processing Conversation $conversation_id"
        
        # Generate unique user ID for this conversation
        local user_id="u_${conversation_id}"
        local session_id=""
        
        # Process each message in the conversation
        local messages=("$message1" "$message2" "$message3" "$message4" "$message5")
        local message_sequence=1
        
        for message in "${messages[@]}"; do
            # Remove quotes from message content
            message=$(echo "$message" | sed 's/^"//;s/"$//')
            
            # Skip empty messages
            if [ -n "$message" ] && [ "$message" != " " ]; then
                # Create session on first message and store the ID
                if [ "$message_sequence" -eq 1 ]; then
                    session_id=$(create_adk_session "$user_id")
                    log "Created ADK session: ${user_id}/${session_id}"
                fi
                
                test_message "$conversation_id" "$message_sequence" "$message" "$session_id" "$user_id"
                message_sequence=$((message_sequence + 1))
                
                # Add delay between messages in same conversation
                sleep 1
            fi
        done
        
        conversation_id=$((conversation_id + 1))
        
        # Add delay between conversations
        sleep 2
        echo ""
    done < "$INPUT_CSV"
}

# Function to generate summary report
generate_summary() {
    local total_tests=$(tail -n +2 "$OUTPUT_CSV" | wc -l)
    local successful_tests=$(tail -n +2 "$OUTPUT_CSV" | awk -F',' '$4 >= 200 && $4 < 300 {count++} END {print count+0}')
    local failed_tests=$((total_tests - successful_tests))
    local avg_response_time=$(tail -n +2 "$OUTPUT_CSV" | awk -F',' '{sum+=$5; count++} END {if(count>0) print sum/count; else print 0}')
    
    echo ""
    print_status "INFO" "========== TEST SUMMARY =========="
    print_status "INFO" "Total Tests: $total_tests"
    print_status "SUCCESS" "Successful: $successful_tests"
    print_status "ERROR" "Failed: $failed_tests"
    print_status "INFO" "Average Response Time: ${avg_response_time}ms"
    print_status "INFO" "Results saved to: $OUTPUT_CSV"
    print_status "INFO" "Session data stored in: $SESSION_STORE_DIR"
    print_status "INFO" "Log file: $LOG_FILE"
    echo ""
    
    log "Test Summary - Total: $total_tests, Success: $successful_tests, Failed: $failed_tests, Avg Time: ${avg_response_time}ms"
}

# Function to cleanup old sessions (optional)
cleanup_old_sessions() {
    if [ -d "$SESSION_STORE_DIR" ]; then
        find "$SESSION_STORE_DIR" -name "session_*.json" -mtime +7 -delete
        log "Cleaned up sessions older than 7 days"
    fi
}

# Main execution
main() {
    print_status "INFO" "Starting Conversation Test Automation"
    print_status "INFO" "Input CSV: $INPUT_CSV"
    print_status "INFO" "API Endpoint: $API_ENDPOINT"
    print_status "INFO" "Output CSV: $OUTPUT_CSV"
    
    # Check if input file exists
    if [ ! -f "$INPUT_CSV" ]; then
        print_status "ERROR" "Input CSV file not found: $INPUT_CSV"
        exit 1
    fi
    
    # Check if jq is installed (for JSON processing)
    if ! command -v jq &> /dev/null; then
        print_status "WARNING" "jq is not installed. Session management will be limited."
    fi
    
    # Initialize
    create_session_dir
    init_result_csv
    cleanup_old_sessions
    
    log "Starting test automation with input: $INPUT_CSV"
    
    # Process conversations
    process_conversations
    
    # Generate summary
    generate_summary
    
    print_status "SUCCESS" "Test automation completed!"
}

# Help function
show_help() {
    echo "Usage: $0 <input_csv> <api_endpoint> [output_csv]"
    echo ""
    echo "Arguments:"
    echo "  input_csv     Path to CSV file containing conversation flows"
    echo "  api_endpoint  API endpoint URL to test"
    echo "  output_csv    Output CSV file for results (optional, default: test_results.csv)"
    echo ""
    echo "Example:"
    echo "  $0 test_conversations.csv http://localhost:3000/api/chat results.csv"
    echo ""
    echo "CSV Format:"
    echo "  - Each row represents a conversation"
    echo "  - Each column represents a message in sequence"
    echo "  - Sessions are maintained per conversation (row)"
}

# Check arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# Run main function
main