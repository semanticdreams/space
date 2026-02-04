# Create upload

`POST` `/uploads`

Creates an intermediate [Upload](/docs/api-reference/uploads/object) object
that you can add [Parts](/docs/api-reference/uploads/part-object) to.
Currently, an Upload can accept at most 8 GB in total and expires after an
hour after you create it.

Once you complete the Upload, we will create a
[File](/docs/api-reference/files/object) object that contains all the parts
you uploaded. This File is usable in the rest of our platform as a regular
File object.

For certain `purpose` values, the correct `mime_type` must be specified. 
Please refer to documentation for the 
[supported MIME types for your use case](/docs/assistants/tools/file-search#supported-files).

For guidance on the proper filename extensions for each purpose, please
follow the documentation on [creating a
File](/docs/api-reference/files/create).


## Request Body

### Content Type: `application/json`

**Type**: object (4 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `filename` | string | Yes |  |  | The name of the file to upload. <br>  |
| `purpose` | string | Yes |  | `assistants`, `batch`, `fine-tune`, `vision` | The intended purpose of the uploaded file. <br>  <br> See the [documentation on File purposes](/docs/api-reference/files/create#files-create-purpose). <br>  |
| `bytes` | integer | Yes |  |  | The number of bytes in the file you are uploading. <br>  |
| `mime_type` | string | Yes |  |  | The MIME type of the file. <br>  <br> This must fall within the supported MIME types for your file purpose. See the supported MIME types for assistants and vision. <br>  |
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
curl https://api.openai.com/v1/uploads \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "purpose": "fine-tune",
    "filename": "training_examples.jsonl",
    "bytes": 2147483648,
    "mime_type": "text/jsonl"
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
  "status": "pending",
  "expires_at": 1719127296
}

```

