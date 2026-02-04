# List messages

`GET` `/threads/{thread_id}/messages`

Returns a list of messages for a given thread.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `thread_id` | string | Yes | The ID of the [thread](/docs/api-reference/threads) the messages belong to. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |
| `order` | string | No | Sort order by the `created_at` timestamp of the objects. `asc` for ascending order and `desc` for descending order. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |
| `before` | string | No | A cursor for use in pagination. `before` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, starting with obj_foo, your subsequent call can include before=obj_foo in order to fetch the previous page of the list. <br>  |
| `run_id` | string | No | Filter messages by the run ID that generated them. <br>  |

## Responses

### 200 - OK

#### Content Type: `application/json`

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  |  |  |
| `data` | array of object (14 properties) | Yes |  |  |  |
| `first_id` | string | Yes |  |  |  |
| `last_id` | string | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

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
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/threads/thread_abc123/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

thread_messages = client.beta.threads.messages.list("thread_abc123")
print(thread_messages.data)

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const threadMessages = await openai.beta.threads.messages.list(
    "thread_abc123"
  );

  console.log(threadMessages.data);
}

main();
```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "id": "msg_abc123",
      "object": "thread.message",
      "created_at": 1699016383,
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
    },
    {
      "id": "msg_abc456",
      "object": "thread.message",
      "created_at": 1699016383,
      "assistant_id": null,
      "thread_id": "thread_abc123",
      "run_id": null,
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": {
            "value": "Hello, what is AI?",
            "annotations": []
          }
        }
      ],
      "attachments": [],
      "metadata": {}
    }
  ],
  "first_id": "msg_abc123",
  "last_id": "msg_abc456",
  "has_more": false
}

```

