# Delete chat completion

`DELETE` `/chat/completions/{completion_id}`

Delete a stored chat completion. Only Chat Completions that have been
created with the `store` parameter set to `true` can be deleted.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `completion_id` | string | Yes | The ID of the chat completion to delete. |

## Responses

### 200 - The chat completion was deleted successfully.

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `chat.completion.deleted` | The type of object being deleted. |
| `id` | string | Yes |  |  | The ID of the chat completion that was deleted. |
| `deleted` | boolean | Yes |  |  | Whether the chat completion was deleted. |
## Examples

### Request Examples

#### curl
```bash
curl -X DELETE https://api.openai.com/v1/chat/completions/chat_abc123 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

completions = client.chat.completions.list()
first_id = completions[0].id
delete_response = client.chat.completions.delete(completion_id=first_id)
print(delete_response)

```

### Response Example

```json
{
  "object": "chat.completion.deleted",
  "id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2",
  "deleted": true
}

```

