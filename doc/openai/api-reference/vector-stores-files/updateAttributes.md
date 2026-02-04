# Update vector store file attributes

`POST` `/vector_stores/{vector_store_id}/files/{file_id}`

Update attributes on a vector store file.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `vector_store_id` | string | Yes | The ID of the vector store the file belongs to. |
| `file_id` | string | Yes | The ID of the file to update attributes. |

## Request Body

### Content Type: `application/json`

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `attributes` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be  <br> useful for storing additional information about the object in a structured  <br> format, and querying for objects via API or the dashboard. Keys are strings  <br> with a maximum length of 64 characters. Values are strings with a maximum  <br> length of 512 characters, booleans, or numbers. <br>  |
|   ↳ (additional properties) | oneOf: string | number | boolean | - | - | - | Additional properties of this object |
## Responses

### 200 - OK

#### Content Type: `application/json`

#### Vector store files

**Type**: object (9 properties)

A list of files attached to a vector store.

#### Properties:

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
**Example:**

```json
{
  "id": "file-abc123",
  "object": "vector_store.file",
  "usage_bytes": 1234,
  "created_at": 1698107661,
  "vector_store_id": "vs_abc123",
  "status": "completed",
  "last_error": null,
  "chunking_strategy": {
    "type": "static",
    "static": {
      "max_chunk_size_tokens": 800,
      "chunk_overlap_tokens": 400
    }
  }
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/vector_stores/{vector_store_id}/files/{file_id} \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"attributes": {"key1": "value1", "key2": 2}}'

```

### Response Example

```json
{
  "id": "file-abc123",
  "object": "vector_store.file",
  "usage_bytes": 1234,
  "created_at": 1699061776,
  "vector_store_id": "vs_abcd",
  "status": "completed",
  "last_error": null,
  "chunking_strategy": {...},
  "attributes": {"key1": "value1", "key2": 2}
}

```

