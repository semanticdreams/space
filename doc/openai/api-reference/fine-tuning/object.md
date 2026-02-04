# The fine-tuning job object

The `fine_tuning.job` object represents a fine-tuning job that has been created through the API.


## Properties

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

## Property Details

### `id` (required)

The object identifier, which can be referenced in the API endpoints.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) for when the fine-tuning job was created.

**Type**: integer

### `error` (required)

For fine-tuning jobs that have `failed`, this will contain more information on the cause of the failure.

**Type**: object (3 properties)

**Nullable**: Yes

**Nested Properties**:

* `code`, `message`, `param`

### `fine_tuned_model` (required)

The name of the fine-tuned model that is being created. The value will be null if the fine-tuning job is still running.

**Type**: string

**Nullable**: Yes

### `finished_at` (required)

The Unix timestamp (in seconds) for when the fine-tuning job was finished. The value will be null if the fine-tuning job is still running.

**Type**: integer

**Nullable**: Yes

### `hyperparameters` (required)

The hyperparameters used for the fine-tuning job. This value will only be returned when running `supervised` jobs.

**Type**: object (3 properties)

**Nested Properties**:

* `batch_size`, `learning_rate_multiplier`, `n_epochs`

### `model` (required)

The base model that is being fine-tuned.

**Type**: string

### `object` (required)

The object type, which is always "fine_tuning.job".

**Type**: string

**Allowed values**: `fine_tuning.job`

### `organization_id` (required)

The organization that owns the fine-tuning job.

**Type**: string

### `result_files` (required)

The compiled results file ID(s) for the fine-tuning job. You can retrieve the results with the [Files API](/docs/api-reference/files/retrieve-contents).

**Type**: array of string

### `status` (required)

The current status of the fine-tuning job, which can be either `validating_files`, `queued`, `running`, `succeeded`, `failed`, or `cancelled`.

**Type**: string

**Allowed values**: `validating_files`, `queued`, `running`, `succeeded`, `failed`, `cancelled`

### `trained_tokens` (required)

The total number of billable tokens processed by this fine-tuning job. The value will be null if the fine-tuning job is still running.

**Type**: integer

**Nullable**: Yes

### `training_file` (required)

The file ID used for training. You can retrieve the training data with the [Files API](/docs/api-reference/files/retrieve-contents).

**Type**: string

### `validation_file` (required)

The file ID used for validation. You can retrieve the validation results with the [Files API](/docs/api-reference/files/retrieve-contents).

**Type**: string

**Nullable**: Yes

### `integrations`

A list of integrations to enable for this fine-tuning job.

**Type**: array of oneOf: object (2 properties)

**Nullable**: Yes

### `seed` (required)

The seed used for the fine-tuning job.

**Type**: integer

### `estimated_finish`

The Unix timestamp (in seconds) for when the fine-tuning job is estimated to finish. The value will be null if the fine-tuning job is not running.

**Type**: integer

**Nullable**: Yes

### `method`

The method used for fine-tuning.

**Type**: object (4 properties)

**Nested Properties**:

* `type`, `supervised`, `dpo`, `reinforcement`

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
  "object": "fine_tuning.job",
  "id": "ftjob-abc123",
  "model": "davinci-002",
  "created_at": 1692661014,
  "finished_at": 1692661190,
  "fine_tuned_model": "ft:davinci-002:my-org:custom_suffix:7q8mpxmy",
  "organization_id": "org-123",
  "result_files": [
      "file-abc123"
  ],
  "status": "succeeded",
  "validation_file": null,
  "training_file": "file-abc123",
  "hyperparameters": {
      "n_epochs": 4,
      "batch_size": 1,
      "learning_rate_multiplier": 1.0
  },
  "trained_tokens": 5768,
  "integrations": [],
  "seed": 0,
  "estimated_finish": 0,
  "method": {
    "type": "supervised",
    "supervised": {
      "hyperparameters": {
        "n_epochs": 4,
        "batch_size": 1,
        "learning_rate_multiplier": 1.0
      }
    }
  },
  "metadata": {
    "key": "value"
  }
}

```

