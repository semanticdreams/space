# Retrieve file content

`GET` `/files/{file_id}/content`

Returns the contents of the specified file.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `file_id` | string | Yes | The ID of the file to use for this request. |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: `string`

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/files/file-abc123/content \
  -H "Authorization: Bearer $OPENAI_API_KEY" > file.jsonl

```

#### python
```python
from openai import OpenAI
client = OpenAI()

content = client.files.content("file-abc123")

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const file = await openai.files.content("file-abc123");

  console.log(file);
}

main();

```

