# List fine-tuning jobs

`GET` `/fine_tuning/jobs`

List your organization's fine-tuning jobs


## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `after` | string | No | Identifier for the last job from the previous pagination request. |
| `limit` | integer | No | Number of fine-tuning jobs to retrieve. |
| `metadata` | object (map of string) | No | Optional metadata filter. To filter, use the syntax `metadata[k]=v`. Alternatively, set `metadata=null` to indicate no metadata. <br>  |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `data` | array of object (19 properties) | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |
| `object` | string | Yes |  | `list` |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The object identifier, which can be referenced in the API endpoints. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the fine-tuning job was created. |
| `error` | object (3 properties) | Yes |  |  | For fine-tuning jobs that have `failed`, this will contain more information on the cause of the failure. |
|   ↳ `param` | string | Yes |  |  | The parameter that was invalid, usually `training_file` or `validation_file`. This field will be null if the failure was not parameter-specific. |
| `fine_tuned_model` | string | Yes |  |  | The name of the fine-tuned model that is being created. The value will be null if the fine-tuning job is still running. |
| `finished_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the fine-tuning job was finished. The value will be null if the fine-tuning job is still running. |
| `hyperparameters` | object (3 properties) | Yes |  |  | The hyperparameters used for the fine-tuning job. This value will only be returned when running `supervised` jobs. |
|   ↳ `n_epochs` | oneOf: string | integer | No | `auto` |  | The number of epochs to train the model for. An epoch refers to one full cycle <br> through the training dataset. <br>  |
| `model` | string | Yes |  |  | The base model that is being fine-tuned. |
| `object` | string | Yes |  | `fine_tuning.job` | The object type, which is always "fine_tuning.job". |
| `organization_id` | string | Yes |  |  | The organization that owns the fine-tuning job. |
| `result_files` | array of string | Yes |  |  | The compiled results file ID(s) for the fine-tuning job. You can retrieve the results with the [Files API](/docs/api-reference/files/retrieve-contents). |
| `status` | string | Yes |  | `validating_files`, `queued`, `running`, `succeeded`, `failed`, `cancelled` | The current status of the fine-tuning job, which can be either `validating_files`, `queued`, `running`, `succeeded`, `failed`, or `cancelled`. |
| `trained_tokens` | integer | Yes |  |  | The total number of billable tokens processed by this fine-tuning job. The value will be null if the fine-tuning job is still running. |
| `training_file` | string | Yes |  |  | The file ID used for training. You can retrieve the training data with the [Files API](/docs/api-reference/files/retrieve-contents). |
| `validation_file` | string | Yes |  |  | The file ID used for validation. You can retrieve the validation results with the [Files API](/docs/api-reference/files/retrieve-contents). |
| `integrations` | array of oneOf: object (2 properties) | No |  |  | A list of integrations to enable for this fine-tuning job. |
| `seed` | integer | Yes |  |  | The seed used for the fine-tuning job. |
| `estimated_finish` | integer | No |  |  | The Unix timestamp (in seconds) for when the fine-tuning job is estimated to finish. The value will be null if the fine-tuning job is not running. |
| `method` | object (4 properties) | No |  |  | The method used for fine-tuning. |
|   ↳ `dpo` | object (1 property) | No |  |  | Configuration for the DPO fine-tuning method. |
|       ↳ `n_epochs` | oneOf: string | integer | No | `auto` |  | The number of epochs to train the model for. An epoch refers to one full cycle through the training dataset. <br>  |
|   ↳ `reinforcement` | object (2 properties) | No |  |  | Configuration for the reinforcement fine-tuning method. |
|       ↳ `n_epochs` | oneOf: string | integer | No | `auto` |  | The number of epochs to train the model for. An epoch refers to one full cycle through the training dataset. <br>  |
|       ↳ `reasoning_effort` | string | No | `default` | `default`, `low`, `medium`, `high` | Level of reasoning effort. <br>  |
|       ↳ `compute_multiplier` | oneOf: string | number | No | `auto` |  | Multiplier on amount of compute used for exploring search space during training. <br>  |
|       ↳ `eval_interval` | oneOf: string | integer | No | `auto` |  | The number of training steps between evaluation runs. <br>  |
|       ↳ `eval_samples` | oneOf: string | integer | No | `auto` |  | Number of evaluation samples to generate per training step. <br>  |
| `metadata` | map | No |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/fine_tuning/jobs?limit=2&metadata[key]=value \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.fine_tuning.jobs.list()

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const list = await openai.fineTuning.jobs.list();

  for await (const fineTune of list) {
    console.log(fineTune);
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
      "object": "fine_tuning.job",
      "id": "ftjob-abc123",
      "model": "gpt-4o-mini-2024-07-18",
      "created_at": 1721764800,
      "fine_tuned_model": null,
      "organization_id": "org-123",
      "result_files": [],
      "status": "queued",
      "validation_file": null,
      "training_file": "file-abc123",
      "metadata": {
        "key": "value"
      }
    },
    { ... },
    { ... }
  ], "has_more": true
}

```

