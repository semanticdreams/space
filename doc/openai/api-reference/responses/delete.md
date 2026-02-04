# Delete a model response

`DELETE` `/responses/{response_id}`

Deletes a model response with the given ID.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `response_id` | string | Yes | The ID of the response to delete. |

## Responses

### 200 - OK

### 404 - Not Found

#### Content Type: `application/json`

**Type**: object (4 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `code` | string | Yes |  |  |  |
| `message` | string | Yes |  |  |  |
| `param` | string | Yes |  |  |  |
| `type` | string | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl -X DELETE https://api.openai.com/v1/responses/resp_123 \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### javascript
```javascript
import OpenAI from "openai";
const client = new OpenAI();

const response = await client.responses.del("resp_123");
console.log(response);  

```

#### python
```python
from openai import OpenAI
client = OpenAI()

response = client.responses.del("resp_123")
print(response)

```

### Response Example

```json
{
  "id": "resp_6786a1bec27481909a17d673315b29f6",
  "object": "response",
  "deleted": true
}

```

