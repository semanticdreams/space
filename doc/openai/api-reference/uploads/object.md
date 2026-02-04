# The upload object

The Upload object can accept byte chunks in the form of Parts.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The Upload unique identifier, which can be referenced in API endpoints. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the Upload was created. |
| `filename` | string | Yes |  |  | The name of the file to be uploaded. |
| `bytes` | integer | Yes |  |  | The intended number of bytes to be uploaded. |
| `purpose` | string | Yes |  |  | The intended purpose of the file. [Please refer here](/docs/api-reference/files/object#files/object-purpose) for acceptable values. |
| `status` | string | Yes |  | `pending`, `completed`, `cancelled`, `expired` | The status of the Upload. |
| `expires_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the Upload will expire. |
| `object` | string | No |  | `upload` | The object type, which is always "upload". |
| `file` | unknown | No |  |  | The ready File object after the Upload is completed. |
|   ↳ `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the file was created. |
|   ↳ `expires_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the file will expire. |
|   ↳ `filename` | string | Yes |  |  | The name of the file. |
|   ↳ `object` | string | Yes |  | `file` | The object type, which is always `file`. |
|   ↳ `purpose` | string | Yes |  | `assistants`, `assistants_output`, `batch`, `batch_output`, `fine-tune`, `fine-tune-results`, `vision` | The intended purpose of the file. Supported values are `assistants`, `assistants_output`, `batch`, `batch_output`, `fine-tune`, `fine-tune-results` and `vision`. |
|   ↳ `status` | string | Yes |  | `uploaded`, `processed`, `error` | Deprecated. The current status of the file, which can be either `uploaded`, `processed`, or `error`. |
|   ↳ `status_details` | string | No |  |  | Deprecated. For details on why a fine-tuning training file failed validation, see the `error` field on `fine_tuning.job`. |

## Property Details

### `id` (required)

The Upload unique identifier, which can be referenced in API endpoints.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) for when the Upload was created.

**Type**: integer

### `filename` (required)

The name of the file to be uploaded.

**Type**: string

### `bytes` (required)

The intended number of bytes to be uploaded.

**Type**: integer

### `purpose` (required)

The intended purpose of the file. [Please refer here](/docs/api-reference/files/object#files/object-purpose) for acceptable values.

**Type**: string

### `status` (required)

The status of the Upload.

**Type**: string

**Allowed values**: `pending`, `completed`, `cancelled`, `expired`

### `expires_at` (required)

The Unix timestamp (in seconds) for when the Upload will expire.

**Type**: integer

### `object`

The object type, which is always "upload".

**Type**: string

**Allowed values**: `upload`

### `file`

The ready File object after the Upload is completed.

**Type**: unknown

**Nullable**: Yes

## Example

```json
{
  "id": "upload_abc123",
  "object": "upload",
  "bytes": 2147483648,
  "created_at": 1719184911,
  "filename": "training_examples.jsonl",
  "purpose": "fine-tune",
  "status": "completed",
  "expires_at": 1719127296,
  "file": {
    "id": "file-xyz321",
    "object": "file",
    "bytes": 2147483648,
    "created_at": 1719186911,
    "filename": "training_examples.jsonl",
    "purpose": "fine-tune",
  }
}

```

