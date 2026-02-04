# List batch

`GET` `/batches`

List your organization's batches.

## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |

## Responses

### 200 - Batch listed successfully.

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `data` | array of object (20 properties) | Yes |  |  |  |
| `first_id` | string | No |  |  |  |
| `last_id` | string | No |  |  |  |
| `has_more` | boolean | Yes |  |  |  |
| `object` | string | Yes |  | `list` |  |


### Items in `data` array

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
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/batches?limit=2 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.batches.list()

```

#### node
```node
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const list = await openai.batches.list();

  for await (const batch of list) {
    console.log(batch);
  }
}

main();

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "id": "batch_abc123",
      "object": "batch",
      "endpoint": "/v1/chat/completions",
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
        "batch_description": "Nightly job",
      }
    },
    { ... },
  ],
  "first_id": "batch_abc123",
  "last_id": "batch_abc456",
  "has_more": true
}

```

