# Create fine-tuning job

`POST` `/fine_tuning/jobs`

Creates a fine-tuning job which begins the process of creating a new model from a given dataset.

Response includes details of the enqueued job including job status and the name of the fine-tuned models once complete.

[Learn more about fine-tuning](/docs/guides/fine-tuning)


## Request Body

### Content Type: `application/json`

**Type**: object (9 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `model` | anyOf: string | string | Yes |  |  | The name of the model to fine-tune. You can select one of the <br> [supported models](/docs/guides/fine-tuning#which-models-can-be-fine-tuned). <br>  |
| `training_file` | string | Yes |  |  | The ID of an uploaded file that contains training data. <br>  <br> See [upload file](/docs/api-reference/files/create) for how to upload a file. <br>  <br> Your dataset must be formatted as a JSONL file. Additionally, you must upload your file with the purpose `fine-tune`. <br>  <br> The contents of the file should differ depending on if the model uses the [chat](/docs/api-reference/fine-tuning/chat-input), [completions](/docs/api-reference/fine-tuning/completions-input) format, or if the fine-tuning method uses the [preference](/docs/api-reference/fine-tuning/preference-input) format. <br>  <br> See the [fine-tuning guide](/docs/guides/fine-tuning) for more details. <br>  |
| `hyperparameters` | object (3 properties) | No |  |  | The hyperparameters used for the fine-tuning job. <br> This value is now deprecated in favor of `method`, and should be passed in under the `method` parameter. <br>  |
|   ↳ `n_epochs` | oneOf: string | integer | No | `auto` |  | The number of epochs to train the model for. An epoch refers to one full cycle <br> through the training dataset. <br>  |
| `suffix` | string | No |  |  | A string of up to 64 characters that will be added to your fine-tuned model name. <br>  <br> For example, a `suffix` of "custom-model-name" would produce a model name like `ft:gpt-4o-mini:openai:custom-model-name:7p4lURel`. <br>  |
| `validation_file` | string | No |  |  | The ID of an uploaded file that contains validation data. <br>  <br> If you provide this file, the data is used to generate validation <br> metrics periodically during fine-tuning. These metrics can be viewed in <br> the fine-tuning results file. <br> The same data should not be present in both train and validation files. <br>  <br> Your dataset must be formatted as a JSONL file. You must upload your file with the purpose `fine-tune`. <br>  <br> See the [fine-tuning guide](/docs/guides/fine-tuning) for more details. <br>  |
| `integrations` | array of object (2 properties) | No |  |  | A list of integrations to enable for your fine-tuning job. |
| `seed` | integer | No |  |  | The seed controls the reproducibility of the job. Passing in the same seed and job parameters should produce the same results, but may differ in rare cases. <br> If a seed is not specified, one will be generated for you. <br>  |
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


### Items in `integrations` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | oneOf: string | Yes |  |  | The type of integration to enable. Currently, only "wandb" (Weights and Biases) is supported. <br>  |
| `wandb` | object (4 properties) | Yes |  |  | The settings for your integration with Weights and Biases. This payload specifies the project that <br> metrics will be sent to. Optionally, you can set an explicit display name for your run, add tags <br> to your run, and set a default entity (team, username, etc) to be associated with your run. <br>  |
|   ↳ `entity` | string | No |  |  | The entity to use for the run. This allows you to set the team or username of the WandB user that you would <br> like associated with the run. If not set, the default entity for the registered WandB API key is used. <br>  |
|   ↳ `tags` | array of string | No |  |  | A list of tags to be attached to the newly created run. These tags are passed through directly to WandB. Some <br> default tags are generated by OpenAI: "openai/finetune", "openai/{base-model}", "openai/{ftjob-abcdef}". <br>  |
## Responses

### 200 - OK

#### Content Type: `application/json`

#### FineTuningJob

**Type**: object (19 properties)

The `fine_tuning.job` object represents a fine-tuning job that has been created through the API.


#### Properties:

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
**Example:**

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

## Examples

