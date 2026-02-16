# Delete file

`DELETE` `/files/{file_id}`

Delete a file.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `file_id` | string | Yes | The ID of the file to use for this request. |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  |  |
| `object` | string | Yes |  | `file` |  |
| `deleted` | boolean | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/files/file-abc123 \
  -X DELETE \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.files.delete("file-abc123")

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const file = await openai.files.del("file-abc123");

  console.log(file);
}

main();
```

### Response Example

```json
{
  "id": "file-abc123",
  "object": "file",
  "deleted": true
}

```

