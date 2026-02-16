# Retrieve file

`GET` `/files/{file_id}`

Returns information about a specific file.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `file_id` | string | Yes | The ID of the file to use for this request. |

## Responses

### 200 - OK

#### Content Type: `application/json`

#### OpenAIFile

The `File` object represents a document that has been uploaded to OpenAI.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The file identifier, which can be referenced in the API endpoints. |
| `bytes` | integer | Yes |  |  | The size of the file, in bytes. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the file was created. |
| `expires_at` | integer | No |  |  | The Unix timestamp (in seconds) for when the file will expire. |
| `filename` | string | Yes |  |  | The name of the file. |
| `object` | string | Yes |  | `file` | The object type, which is always `file`. |
| `purpose` | string | Yes |  | `assistants`, `assistants_output`, `batch`, `batch_output`, `fine-tune`, `fine-tune-results`, `vision` | The intended purpose of the file. Supported values are `assistants`, `assistants_output`, `batch`, `batch_output`, `fine-tune`, `fine-tune-results` and `vision`. |
| `status` | string | Yes |  | `uploaded`, `processed`, `error` | Deprecated. The current status of the file, which can be either `uploaded`, `processed`, or `error`. |
| `status_details` | string | No |  |  | Deprecated. For details on why a fine-tuning training file failed validation, see the `error` field on `fine_tuning.job`. |
**Example:**

```json
{
  "id": "file-abc123",
  "object": "file",
  "bytes": 120000,
  "created_at": 1677610602,
  "expires_at": 1680202602,
  "filename": "salesOverview.pdf",
  "purpose": "assistants",
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/files/file-abc123 \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.files.retrieve("file-abc123")

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const file = await openai.files.retrieve("file-abc123");

  console.log(file);
}

main();
```

### Response Example

```json
{
  "id": "file-abc123",
  "object": "file",
  "bytes": 120000,
  "created_at": 1677610602,
  "filename": "mydata.jsonl",
  "purpose": "fine-tune",
}

```

