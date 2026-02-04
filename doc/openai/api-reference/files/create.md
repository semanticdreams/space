# Upload file

`POST` `/files`

Upload a file that can be used across various endpoints. Individual files can be up to 512 MB, and the size of all files uploaded by one organization can be up to 100 GB.

The Assistants API supports files up to 2 million tokens and of specific file types. See the [Assistants Tools guide](/docs/assistants/tools) for details.

The Fine-tuning API only supports `.jsonl` files. The input also has certain required formats for fine-tuning [chat](/docs/api-reference/fine-tuning/chat-input) or [completions](/docs/api-reference/fine-tuning/completions-input) models.

The Batch API only supports `.jsonl` files up to 200 MB in size. The input also has a specific required [format](/docs/api-reference/batch/request-input).

Please [contact us](https://help.openai.com/) if you need to increase these storage limits.


## Request Body

### Content Type: `multipart/form-data`

**Type**: object (2 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `file` | string | Yes |  |  | The File object (not file name) to be uploaded. <br>  |
| `purpose` | string | Yes |  | `assistants`, `batch`, `fine-tune`, `vision`, `user_data`, `evals` | The intended purpose of the uploaded file. One of: - `assistants`: Used in the Assistants API - `batch`: Used in the Batch API - `fine-tune`: Used for fine-tuning - `vision`: Images used for vision fine-tuning - `user_data`: Flexible file type for any purpose - `evals`: Used for eval data sets <br>  |
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
curl https://api.openai.com/v1/files \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F purpose="fine-tune" \
  -F file="@mydata.jsonl"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.files.create(
  file=open("mydata.jsonl", "rb"),
  purpose="fine-tune"
)

```

#### node.js
```javascript
import fs from "fs";
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const file = await openai.files.create({
    file: fs.createReadStream("mydata.jsonl"),
    purpose: "fine-tune",
  });

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

