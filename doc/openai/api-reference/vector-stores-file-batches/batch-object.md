# The vector store files batch object

A batch of files attached to a vector store.

## Properties

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

## Property Details

### `id` (required)

The identifier, which can be referenced in API endpoints.

**Type**: string

### `object` (required)

The object type, which is always `vector_store.file_batch`.

**Type**: string

**Allowed values**: `vector_store.files_batch`

### `created_at` (required)

The Unix timestamp (in seconds) for when the vector store files batch was created.

**Type**: integer

### `vector_store_id` (required)

The ID of the [vector store](/docs/api-reference/vector-stores/object) that the [File](/docs/api-reference/files) is attached to.

**Type**: string

### `status` (required)

The status of the vector store files batch, which can be either `in_progress`, `completed`, `cancelled` or `failed`.

**Type**: string

**Allowed values**: `in_progress`, `completed`, `cancelled`, `failed`

### `file_counts` (required)

**Type**: object (5 properties)

**Nested Properties**:

* `in_progress`, `completed`, `failed`, `cancelled`, `total`

## Example

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

