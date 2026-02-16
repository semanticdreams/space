# Retrieve vector store

`GET` `/vector_stores/{vector_store_id}`

Retrieves a vector store.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `vector_store_id` | string | Yes | The ID of the vector store to retrieve. |

## Responses

### 200 - OK

#### Content Type: `application/json`

#### Vector store

**Type**: object (11 properties)

A vector store is a collection of processed files can be used by the `file_search` tool.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `vector_store` | The object type, which is always `vector_store`. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the vector store was created. |
| `name` | string | Yes |  |  | The name of the vector store. |
| `usage_bytes` | integer | Yes |  |  | The total number of bytes used by the files in the vector store. |
| `file_counts` | object (5 properties) | Yes |  |  |  |
|   ↳ `failed` | integer | Yes |  |  | The number of files that have failed to process. |
|   ↳ `cancelled` | integer | Yes |  |  | The number of files that were cancelled. |
|   ↳ `total` | integer | Yes |  |  | The total number of files. |
| `status` | string | Yes |  | `expired`, `in_progress`, `completed` | The status of the vector store, which can be either `expired`, `in_progress`, or `completed`. A status of `completed` indicates that the vector store is ready for use. |
| `expires_after` | object (2 properties) | No |  |  | The expiration policy for a vector store. |
| `expires_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the vector store will expire. |
| `last_active_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the vector store was last active. |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
**Example:**

```json
{
  "id": "vs_123",
  "object": "vector_store",
  "created_at": 1698107661,
  "usage_bytes": 123456,
  "last_active_at": 1698107661,
  "name": "my_vector_store",
  "status": "completed",
  "file_counts": {
    "in_progress": 0,
    "completed": 100,
    "cancelled": 0,
    "failed": 0,
    "total": 100
  },
  "last_used_at": 1698107661
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/vector_stores/vs_abc123 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -H "OpenAI-Beta: assistants=v2"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

vector_store = client.vector_stores.retrieve(
  vector_store_id="vs_abc123"
)
print(vector_store)

```

#### node.js
```javascript
import OpenAI from "openai";
const openai = new OpenAI();

async function main() {
  const vectorStore = await openai.vectorStores.retrieve(
    "vs_abc123"
  );
  console.log(vectorStore);
}

main();

```

### Response Example

```json
{
  "id": "vs_abc123",
  "object": "vector_store",
  "created_at": 1699061776
}

```

