# The upload part object

The upload Part represents a chunk of bytes we can add to an Upload object.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The upload Part unique identifier, which can be referenced in API endpoints. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the Part was created. |
| `upload_id` | string | Yes |  |  | The ID of the Upload object that this Part was added to. |
| `object` | string | Yes |  | `upload.part` | The object type, which is always `upload.part`. |

## Property Details

### `id` (required)

The upload Part unique identifier, which can be referenced in API endpoints.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) for when the Part was created.

**Type**: integer

### `upload_id` (required)

The ID of the Upload object that this Part was added to.

**Type**: string

### `object` (required)

The object type, which is always `upload.part`.

**Type**: string

**Allowed values**: `upload.part`

## Example

```json
{
    "id": "part_def456",
    "object": "upload.part",
    "created_at": 1719186911,
    "upload_id": "upload_abc123"
}

```

