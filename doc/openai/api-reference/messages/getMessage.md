# Retrieve message

`GET` `/threads/{thread_id}/messages/{message_id}`

Retrieve a message.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `thread_id` | string | Yes | The ID of the [thread](/docs/api-reference/threads) to which this message belongs. |
| `message_id` | string | Yes | The ID of the message to retrieve. |

## Responses

### 200 - OK

#### Content Type: `application/json`

#### The message object

**Type**: object (14 properties)

Represents a message within a [thread](/docs/api-reference/threads).

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `thread.message` | The object type, which is always `thread.message`. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the message was created. |
| `thread_id` | string | Yes |  |  | The [thread](/docs/api-reference/threads) ID that this message belongs to. |
| `status` | string | Yes |  | `in_progress`, `incomplete`, `completed` | The status of the message, which can be either `in_progress`, `incomplete`, or `completed`. |
| `incomplete_details` | object (1 property) | Yes |  |  | On an incomplete message, details about why the message is incomplete. |
| `completed_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the message was completed. |
| `incomplete_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the message was marked as incomplete. |
| `role` | string | Yes |  | `user`, `assistant` | The entity that produced the message. One of `user` or `assistant`. |
| `content` | array of oneOf: object (2 properties) | object (2 properties) | object (2 properties) | object (2 properties) | Yes |  |  | The content of the message in array of text and/or images. |
| `assistant_id` | string | Yes |  |  | If applicable, the ID of the [assistant](/docs/api-reference/assistants) that authored this message. |
| `run_id` | string | Yes |  |  | The ID of the [run](/docs/api-reference/runs) associated with the creation of this message. Value is `null` when messages are created manually using the create message or create thread endpoints. |
| `attachments` | array of object (2 properties) | Yes |  |  | A list of files attached to the message, and the tools they were added to. |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |


### Items in `attachments` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `file_id` | string | No |  |  | The ID of the file to attach to the message. |
| `tools` | array of oneOf: object (1 property) | object (1 property) | No |  |  | The tools to add this file to. |
**Example:**

```json
{
  "id": "msg_abc123",
  "object": "thread.message",
  "created_at": 1698983503,
  "thread_id": "thread_abc123",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": {
        "value": "Hi! How can I help you today?",
        "annotations": []
      }
    }
  ],
  "assistant_id": "asst_abc123",
  "run_id": "run_abc123",
  "attachments": [],
  "metadata": {}
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/threads/thread_abc123/messages/msg_abc123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

message = client.beta.threads.messages.retrieve(
  message_id="msg_abc123",
  thread_id="thread_abc123",
)
print(message)

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const message = await openai.beta.threads.messages.retrieve(
    "thread_abc123",
    "msg_abc123"
  );

  console.log(message);
}

main();
```

### Response Example

```json
{
  "id": "msg_abc123",
  "object": "thread.message",
  "created_at": 1699017614,
  "assistant_id": null,
  "thread_id": "thread_abc123",
  "run_id": null,
  "role": "user",
  "content": [
    {
      "type": "text",
      "text": {
        "value": "How does AI work? Explain it in simple terms.",
        "annotations": []
      }
    }
  ],
  "attachments": [],
  "metadata": {}
}

```

