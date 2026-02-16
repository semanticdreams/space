# Delete vector store file

`DELETE` `/vector_stores/{vector_store_id}/files/{file_id}`

Delete a vector store file. This will remove the file from the vector store but the file itself will not be deleted. To delete the file, use the [delete file](/docs/api-reference/files/delete) endpoint.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `vector_store_id` | string | Yes | The ID of the vector store that the file belongs to. |
| `file_id` | string | Yes | The ID of the file to delete. |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  |  |
| `deleted` | boolean | Yes |  |  |  |
| `object` | string | Yes |  | `vector_store.file.deleted` |  |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/vector_stores/vs_abc123/files/file-abc123 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -H "OpenAI-Beta: assistants=v2" \
  -X DELETE

```

#### python
```python
from openai import OpenAI
client = OpenAI()

deleted_vector_store_file = client.vector_stores.files.delete(
    vector_store_id="vs_abc123",
    file_id="file-abc123"
)
print(deleted_vector_store_file)

```

#### node.js
```javascript
import OpenAI from "openai";
const openai = new OpenAI();

async function main() {
  const deletedVectorStoreFile = await openai.vectorStores.files.del(
    "vs_abc123",
    "file-abc123"
  );
  console.log(deletedVectorStoreFile);
}

main();

```

### Response Example

```json
{
  id: "file-abc123",
  object: "vector_store.file.deleted",
  deleted: true
}

```

