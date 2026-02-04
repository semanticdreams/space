# Retrieve vector store file batch

`GET` `/vector_stores/{vector_store_id}/file_batches/{batch_id}`

Retrieves a vector store file batch.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `vector_store_id` | string | Yes | The ID of the vector store that the file batch belongs to. |
| `batch_id` | string | Yes | The ID of the file batch being retrieved. |

## Responses

### 200 - OK

#### Content Type: `application/json`

#### Vector store file batch

**Type**: object (6 properties)

A batch of files attached to a vector store.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `vector_store.files_batch` | The object type, which is always `vector_store.file_batch`. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the vector store files batch was created. |
| `vector_store_id` | string | Yes |  |  | The ID of the [vector store](/docs/api-reference/vector-stores/object) that the [File](/docs/api-reference/files) is attached to. |
| `status` | string | Yes |  | `in_progress`, `completed`, `cancelled`, `failed` | The status of the vector store files batch, which can be either `in_progress`, `completed`, `cancelled` or `failed`. |
| `file_counts` | object (5 properties) | Yes |  |  |  |
|   ↳ `failed` | integer | Yes |  |  | The number of files that have failed to process. |
|   ↳ `cancelled` | integer | Yes |  |  | The number of files that where cancelled. |
|   ↳ `total` | integer | Yes |  |  | The total number of files. |
**Example:**

```json
{
  "id": "vsfb_123",
  "object": "vector_store.files_batch",
  "created_at": 1698107661,
  "vector_store_id": "vs_abc123",
  "status": "completed",
  "file_counts": {
    "in_progress": 0,
    "completed": 100,
    "failed": 0,
    "cancelled": 0,
    "total": 100
  }
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/vector_stores/vs_abc123/files_batches/vsfb_abc123 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -H "OpenAI-Beta: assistants=v2"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

vector_store_file_batch = client.vector_stores.file_batches.retrieve(
  vector_store_id="vs_abc123",
  batch_id="vsfb_abc123"
)
print(vector_store_file_batch)

```

#### node.js
```javascript
import OpenAI from "openai";
const openai = new OpenAI();

async function main() {
  const vectorStoreFileBatch = await openai.vectorStores.fileBatches.retrieve(
    "vs_abc123",
    "vsfb_abc123"
  );
  console.log(vectorStoreFileBatch);
}

main();

```

### Response Example

```json
{
  "id": "vsfb_abc123",
  "object": "vector_store.file_batch",
  "created_at": 1699061776,
  "vector_store_id": "vs_abc123",
  "status": "in_progress",
  "file_counts": {
    "in_progress": 1,
    "completed": 1,
    "failed": 0,
    "cancelled": 0,
    "total": 0,
  }
}

```

