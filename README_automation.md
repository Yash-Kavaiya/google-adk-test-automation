# Conversation Test Automation

This automation solution tests conversational flows where each row represents a different conversation and each column represents sequential messages in that conversation.

## Files Created

1. **test_conversations.csv** - Sample 5x5 input file with conversation flows
2. **test_automation.sh** - Main automation script
3. **test_results.csv** - Output file with detailed results (generated after running)

## Usage

### Basic Usage
```bash
chmod +x test_automation.sh
./test_automation.sh test_conversations.csv http://your-api-endpoint.com/chat
```

### Full Usage
```bash
./test_automation.sh <input_csv> <api_endpoint> [output_csv]
```

### Example
```bash
./test_automation.sh test_conversations.csv http://localhost:3000/api/chat my_results.csv
```

## Input CSV Format

- **Rows**: Each row = one conversation/session
- **Columns**: Each column = next message in that conversation
- **Sessions**: Automatically maintained per conversation row

```csv
message1,message2,message3,message4,message5
"Hello, I want to check my order","My order ID is 12345","Can you tell me the status?","When will it be delivered?","Thank you for your help"
"Hi, I want to check my status","My order ID is 123","Is it shipped yet?","What's the tracking number?","Perfect, thanks!"
```

## Output CSV Fields

- `conversation_id` - Row number from input
- `message_sequence` - Column number in conversation  
- `message_content` - The actual message sent
- `response_status` - HTTP status code
- `response_time_ms` - Response time in milliseconds
- `response_body` - API response content
- `session_id` - Unique session identifier
- `timestamp` - When the test was executed
- `error_message` - Any error details

## Features

- ✅ **Session Management**: Each conversation maintains its own session
- ✅ **Detailed Logging**: Complete results saved to CSV
- ✅ **Color-coded Output**: Success/error status with colors
- ✅ **Response Time Tracking**: Measures API response times
- ✅ **Error Handling**: Captures and logs all errors
- ✅ **Session Storage**: Maintains conversation history
- ✅ **Summary Report**: Shows test statistics
- ✅ **Cleanup**: Removes old session files automatically

## Session Management

- Each conversation row gets a unique session ID
- Session data stored in `./sessions/` directory
- Conversation history maintained throughout the flow
- Sessions automatically expire after 7 days

## Dependencies

- `curl` - For API calls
- `jq` - For JSON processing (optional but recommended)

Install jq on Ubuntu/Debian: `sudo apt install jq`
Install jq on macOS: `brew install jq`

## Example Output

```
✓ Conv 1, Msg 1: 200
✓ Conv 1, Msg 2: 200
✗ Conv 2, Msg 1: 404
✓ Conv 2, Msg 2: 200

========== TEST SUMMARY ==========
Total Tests: 25
Successful: 23
Failed: 2
Average Response Time: 145ms
```