# Delete vector store

`DELETE` `/vector_stores/{vector_store_id}`

Delete a vector store.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `vector_store_id` | string | Yes | The ID of the vector store to delete. |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  |  |
| `deleted` | boolean | Yes |  |  |  |
| `object` | string | Yes |  | `vector_store.deleted` |  |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/vector_stores/vs_abc123 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -H "OpenAI-Beta: assistants=v2" \
  -X DELETE

```

#### python
```python
from openai import OpenAI
client = OpenAI()

deleted_vector_store = client.vector_stores.delete(
  vector_store_id="vs_abc123"
)
print(deleted_vector_store)

```

#### node.js
```javascript
import OpenAI from "openai";
const openai = new OpenAI();

async function main() {
  const deletedVectorStore = await openai.vectorStores.del(
    "vs_abc123"
  );
  console.log(deletedVectorStore);
}

main();

```

### Response Example

```json
{
  id: "vs_abc123",
  object: "vector_store.deleted",
  deleted: true
}

```

