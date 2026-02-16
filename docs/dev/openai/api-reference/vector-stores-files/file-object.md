# The vector store file object

A list of files attached to a vector store.

## Properties

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

## Property Details

### `id` (required)

The identifier, which can be referenced in API endpoints.

**Type**: string

### `object` (required)

The object type, which is always `vector_store.file`.

**Type**: string

**Allowed values**: `vector_store.file`

### `usage_bytes` (required)

The total vector store usage in bytes. Note that this may be different from the original file size.

**Type**: integer

### `created_at` (required)

The Unix timestamp (in seconds) for when the vector store file was created.

**Type**: integer

### `vector_store_id` (required)

The ID of the [vector store](/docs/api-reference/vector-stores/object) that the [File](/docs/api-reference/files) is attached to.

**Type**: string

### `status` (required)

The status of the vector store file, which can be either `in_progress`, `completed`, `cancelled`, or `failed`. The status `completed` indicates that the vector store file is ready for use.

**Type**: string

**Allowed values**: `in_progress`, `completed`, `cancelled`, `failed`

### `last_error` (required)

The last error associated with this vector store file. Will be `null` if there are no errors.

**Type**: object (2 properties)

**Nullable**: Yes

**Nested Properties**:

* `code`, `message`

### `chunking_strategy`

The strategy used to chunk the file.

**Type**: object

### `attributes`

Set of 16 key-value pairs that can be attached to an object. This can be 
useful for storing additional information about the object in a structured 
format, and querying for objects via API or the dashboard. Keys are strings 
with a maximum length of 64 characters. Values are strings with a maximum 
length of 512 characters, booleans, or numbers.


**Type**: map

**Nullable**: Yes

## Example

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

