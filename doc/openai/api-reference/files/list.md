# List files

`GET` `/files`

Returns a list of files.

## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `purpose` | string | No | Only return files with the given purpose. |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 10,000, and the default is 10,000. <br>  |
| `order` | string | No | Sort order by the `created_at` timestamp of the objects. `asc` for ascending order and `desc` for descending order. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  |  |  |
| `data` | array of unknown | Yes |  |  |  |
| `first_id` | string | Yes |  |  |  |
| `last_id` | string | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

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
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/files \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.files.list()

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const list = await openai.files.list();

  for await (const file of list) {
    console.log(file);
  }
}

main();
```

### Response Example

```json
{
  "data": [
    {
      "id": "file-abc123",
      "object": "file",
      "bytes": 175,
      "created_at": 1613677385,
      "filename": "salesOverview.pdf",
      "purpose": "assistants",
    },
    {
      "id": "file-abc123",
      "object": "file",
      "bytes": 140,
      "created_at": 1613779121,
      "filename": "puppy.jsonl",
      "purpose": "fine-tune",
    }
  ],
  "object": "list"
}

```

