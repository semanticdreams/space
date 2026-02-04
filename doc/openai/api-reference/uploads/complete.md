# Complete upload

`POST` `/uploads/{upload_id}/complete`

Completes the [Upload](/docs/api-reference/uploads/object). 

Within the returned Upload object, there is a nested [File](/docs/api-reference/files/object) object that is ready to use in the rest of the platform.

You can specify the order of the Parts by passing in an ordered list of the Part IDs.

The number of bytes uploaded upon completion must match the number of bytes initially specified when creating the Upload object. No Parts may be added after an Upload is completed.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `upload_id` | string | Yes | The ID of the Upload. <br>  |

## Request Body

### Content Type: `application/json`

**Type**: object (2 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `part_ids` | array of string | Yes |  |  | The ordered list of Part IDs. <br>  |
| `md5` | string | No |  |  | The optional md5 checksum for the file contents to verify if the bytes uploaded matches what you expect. <br>  |
## Responses

### 200 - OK

#### Content Type: `application/json`

#### Upload

**Type**: object (9 properties)

The Upload object can accept byte chunks in the form of Parts.


#### Properties:

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
**Example:**

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

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/uploads/upload_abc123/complete
  -d '{
    "part_ids": ["part_def456", "part_ghi789"]
  }'

```

### Response Example

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

