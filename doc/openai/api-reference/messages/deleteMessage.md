# Delete message

`DELETE` `/threads/{thread_id}/messages/{message_id}`

Deletes a message.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `thread_id` | string | Yes | The ID of the thread to which this message belongs. |
| `message_id` | string | Yes | The ID of the message to delete. |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  |  |
| `deleted` | boolean | Yes |  |  |  |
| `object` | string | Yes |  | `thread.message.deleted` |  |
## Examples

### Request Examples

#### curl
```bash
curl -X DELETE https://api.openai.com/v1/threads/thread_abc123/messages/msg_abc123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

deleted_message = client.beta.threads.messages.delete(
  message_id="msg_abc12",
  thread_id="thread_abc123",
)
print(deleted_message)

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const deletedMessage = await openai.beta.threads.messages.del(
    "thread_abc123",
    "msg_abc123"
  );

  console.log(deletedMessage);
}
```

### Response Example

```json
{
  "id": "msg_abc123",
  "object": "thread.message.deleted",
  "deleted": true
}

```

