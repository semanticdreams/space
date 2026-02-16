# Delete assistant

`DELETE` `/assistants/{assistant_id}`

Delete an assistant.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `assistant_id` | string | Yes | The ID of the assistant to delete. |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  |  |
| `deleted` | boolean | Yes |  |  |  |
| `object` | string | Yes |  | `assistant.deleted` |  |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/assistants/asst_abc123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2" \
  -X DELETE

```

#### python
```python
from openai import OpenAI
client = OpenAI()

response = client.beta.assistants.delete("asst_abc123")
print(response)

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const response = await openai.beta.assistants.del("asst_abc123");

  console.log(response);
}
main();
```

### Response Example

```json
{
  "id": "asst_abc123",
  "object": "assistant.deleted",
  "deleted": true
}

```

