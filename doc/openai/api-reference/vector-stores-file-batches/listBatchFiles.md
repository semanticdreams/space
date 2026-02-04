# List vector store files in a batch

`GET` `/vector_stores/{vector_store_id}/file_batches/{batch_id}/files`

Returns a list of vector store files in a batch.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `vector_store_id` | string | Yes | The ID of the vector store that the files belong to. |
| `batch_id` | string | Yes | The ID of the file batch that the files belong to. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |
| `order` | string | No | Sort order by the `created_at` timestamp of the objects. `asc` for ascending order and `desc` for descending order. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |
| `before` | string | No | A cursor for use in pagination. `before` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, starting with obj_foo, your subsequent call can include before=obj_foo in order to fetch the previous page of the list. <br>  |
| `filter` | string | No | Filter by file status. One of `in_progress`, `completed`, `failed`, `cancelled`. |

## Responses

### 200 - OK

#### Content Type: `application/json`

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  |  |  |
| `data` | array of object (9 properties) | Yes |  |  |  |
| `first_id` | string | Yes |  |  |  |
| `last_id` | string | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `vector_store.file` | The object type, which is always `vector_store.file`. |
| `usage_bytes` | integer | Yes |  |  | The total vector store usage in bytes. Note that this may be different from the original file size. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the vector store file was created. |
| `vector_store_id` | string | Yes |  |  | The ID of the [vector store](/docs/api-reference/vector-stores/object) that the [File](/docs/api-reference/files) is attached to. |
| `status` | string | Yes |  | `in_progress`, `completed`, `cancelled`, `failed` | The status of the vector store file, which can be either `in_progress`, `completed`, `cancelled`, or `failed`. The status `completed` indicates that the vector store file is ready for use. |
| `last_error` | object (2 properties) | Yes |  |  | The last error associated with this vector store file. Will be `null` if there are no errors. |
| `chunking_strategy` | object | No |  |  | The strategy used to chunk the file. |
| `attributes` | map | No |  |  | Set of 16 key-value pairs that can be attached to an object. This can be  <br> useful for storing additional information about the object in a structured  <br> format, and querying for objects via API or the dashboard. Keys are strings  <br> with a maximum length of 64 characters. Values are strings with a maximum  <br> length of 512 characters, booleans, or numbers. <br>  |
|   ↳ (additional properties) | oneOf: string | number | boolean | - | - | - | Additional properties of this object |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/vector_stores/vs_abc123/files_batches/vsfb_abc123/files \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -H "OpenAI-Beta: assistants=v2"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

vector_store_files = client.vector_stores.file_batches.list_files(
  vector_store_id="vs_abc123",
  batch_id="vsfb_abc123"
)
print(vector_store_files)

```

#### node.js
```javascript
import OpenAI from "openai";
const openai = new OpenAI();

async function main() {
  const vectorStoreFiles = await openai.vectorStores.fileBatches.listFiles(
    "vs_abc123",
    "vsfb_abc123"
  );
  console.log(vectorStoreFiles);
}

main();

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "id": "file-abc123",
      "object": "vector_store.file",
      "created_at": 1699061776,
      "vector_store_id": "vs_abc123"
    },
    {
      "id": "file-abc456",
      "object": "vector_store.file",
      "created_at": 1699061776,
      "vector_store_id": "vs_abc123"
    }
  ],
  "first_id": "file-abc123",
  "last_id": "file-abc456",
  "has_more": false
}

```

