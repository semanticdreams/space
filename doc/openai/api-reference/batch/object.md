# The batch object

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  |  |
| `object` | string | Yes |  | `batch` | The object type, which is always `batch`. |
| `endpoint` | string | Yes |  |  | The OpenAI API endpoint used by the batch. |
| `errors` | object (2 properties) | No |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `code` | string | No |  |  | An error code identifying the error type. |
| `message` | string | No |  |  | A human-readable message providing more details about the error. |
| `param` | string | No |  |  | The name of the parameter that caused the error, if applicable. |
| `line` | integer | No |  |  | The line number of the input file where the error occurred, if applicable. |
| `input_file_id` | string | Yes |  |  | The ID of the input file for the batch. |
| `completion_window` | string | Yes |  |  | The time frame within which the batch should be processed. |
| `status` | string | Yes |  | `validating`, `failed`, `in_progress`, `finalizing`, `completed`, `expired`, `cancelling`, `cancelled` | The current status of the batch. |
| `output_file_id` | string | No |  |  | The ID of the file containing the outputs of successfully executed requests. |
| `error_file_id` | string | No |  |  | The ID of the file containing the outputs of requests with errors. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the batch was created. |
| `in_progress_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the batch started processing. |
| `expires_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the batch will expire. |
| `finalizing_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the batch started finalizing. |
| `completed_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the batch was completed. |
| `failed_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the batch failed. |
| `expired_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the batch expired. |
| `cancelling_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the batch started cancelling. |
| `cancelled_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the batch was cancelled. |
| `request_counts` | object (3 properties) | No |  |  | The request counts for different statuses within the batch. |
|   ↳ `failed` | integer | Yes |  |  | Number of requests that have failed. |
| `metadata` | map | No |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |

## Property Details

### `id` (required)

**Type**: string

### `object` (required)

The object type, which is always `batch`.

**Type**: string

**Allowed values**: `batch`

### `endpoint` (required)

The OpenAI API endpoint used by the batch.

**Type**: string

### `errors`

**Type**: object (2 properties)

**Nested Properties**:

* `object`, `data`

### `input_file_id` (required)

The ID of the input file for the batch.

**Type**: string

### `completion_window` (required)

The time frame within which the batch should be processed.

**Type**: string

### `status` (required)

The current status of the batch.

**Type**: string

**Allowed values**: `validating`, `failed`, `in_progress`, `finalizing`, `completed`, `expired`, `cancelling`, `cancelled`

### `output_file_id`

The ID of the file containing the outputs of successfully executed requests.

**Type**: string

### `error_file_id`

The ID of the file containing the outputs of requests with errors.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) for when the batch was created.

**Type**: integer

### `in_progress_at`

The Unix timestamp (in seconds) for when the batch started processing.

**Type**: integer

### `expires_at`

The Unix timestamp (in seconds) for when the batch will expire.

**Type**: integer

### `finalizing_at`

The Unix timestamp (in seconds) for when the batch started finalizing.

**Type**: integer

### `completed_at`

The Unix timestamp (in seconds) for when the batch was completed.

**Type**: integer

### `failed_at`

The Unix timestamp (in seconds) for when the batch failed.

**Type**: integer

### `expired_at`

The Unix timestamp (in seconds) for when the batch expired.

**Type**: integer

### `cancelling_at`

The Unix timestamp (in seconds) for when the batch started cancelling.

**Type**: integer

### `cancelled_at`

The Unix timestamp (in seconds) for when the batch was cancelled.

**Type**: integer

### `request_counts`

The request counts for different statuses within the batch.

**Type**: object (3 properties)

**Nested Properties**:

* `total`, `completed`, `failed`

### `metadata`

Set of 16 key-value pairs that can be attached to an object. This can be
useful for storing additional information about the object in a structured
format, and querying for objects via API or the dashboard. 

Keys are strings with a maximum length of 64 characters. Values are strings
with a maximum length of 512 characters.


**Type**: map

**Nullable**: Yes

## Example

```json
{
  "id": "batch_abc123",
  "object": "batch",
  "endpoint": "/v1/completions",
  "errors": null,
  "input_file_id": "file-abc123",
  "completion_window": "24h",
  "status": "completed",
  "output_file_id": "file-cvaTdG",
  "error_file_id": "file-HOWS94",
  "created_at": 1711471533,
  "in_progress_at": 1711471538,
  "expires_at": 1711557933,
  "finalizing_at": 1711493133,
  "completed_at": 1711493163,
  "failed_at": null,
  "expired_at": null,
  "cancelling_at": null,
  "cancelled_at": null,
  "request_counts": {
    "total": 100,
    "completed": 95,
    "failed": 5
  },
  "metadata": {
    "customer_id": "user_123456789",
    "batch_description": "Nightly eval job",
  }
}

```

