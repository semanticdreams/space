# List input items

`GET` `/responses/{response_id}/input_items`

Returns a list of input items for a given response.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `response_id` | string | Yes | The ID of the response to retrieve input items for. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between <br> 1 and 100, and the default is 20. <br>  |
| `order` | string | No | The order to return the input items in. Default is `asc`. <br> - `asc`: Return the input items in ascending order. <br> - `desc`: Return the input items in descending order. <br>  |
| `after` | string | No | An item ID to list items after, used in pagination. <br>  |
| `before` | string | No | An item ID to list items before, used in pagination. <br>  |
| `include` | array of string | No | Additional fields to include in the response. See the `include` <br> parameter for Response creation above for more information. <br>  |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (5 properties)

A list of Response items.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `list` | The type of object returned, must be `list`. |
| `data` | array of oneOf: object (5 properties) | object (5 properties) | object (5 properties) | object (6 properties) | object (6 properties) | object (3 properties) | object (6 properties) | object (5 properties) | Yes |  |  | A list of items used to generate this response. |
| `has_more` | boolean | Yes |  |  | Whether there are more items available. |
| `first_id` | string | Yes |  |  | The ID of the first item in the list. |
| `last_id` | string | Yes |  |  | The ID of the last item in the list. |
**Example:**

```json
{
  "object": "list",
  "data": [
    {
      "id": "msg_abc123",
      "type": "message",
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "Tell me a three sentence bedtime story about a unicorn."
        }
      ]
    }
  ],
  "first_id": "msg_abc123",
  "last_id": "msg_abc123",
  "has_more": false
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/responses/resp_abc123/input_items \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### javascript
```javascript
import OpenAI from "openai";
const client = new OpenAI();

const response = await client.responses.inputItems.list("resp_123");
console.log(response.data);  

```

#### python
```python
from openai import OpenAI
client = OpenAI()

response = client.responses.input_items.list("resp_123")
print(response.data)

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "id": "msg_abc123",
      "type": "message",
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "Tell me a three sentence bedtime story about a unicorn."
        }
      ]
    }
  ],
  "first_id": "msg_abc123",
  "last_id": "msg_abc123",
  "has_more": false
}

```

