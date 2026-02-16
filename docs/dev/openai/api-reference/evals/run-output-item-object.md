# The eval run output item object

A schema representing an evaluation run output item.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes | `eval.run.output_item` | `eval.run.output_item` | The type of the object. Always "eval.run.output_item". |
| `id` | string | Yes |  |  | Unique identifier for the evaluation run output item. |
| `run_id` | string | Yes |  |  | The identifier of the evaluation run associated with this output item. |
| `eval_id` | string | Yes |  |  | The identifier of the evaluation group. |
| `created_at` | integer | Yes |  |  | Unix timestamp (in seconds) when the evaluation run was created. |
| `status` | string | Yes |  |  | The status of the evaluation run. |
| `datasource_item_id` | integer | Yes |  |  | The identifier for the data source item. |
| `datasource_item` | object (map of object) | Yes |  |  | Details of the input data source item. |
|   ↳ (additional properties) | object | - | - | - | Additional properties of this object |
| `results` | array of object (map of object) | Yes |  |  | A list of results from the evaluation run. |
| `sample` | object (10 properties) | Yes |  |  | A sample containing the input and output of the evaluation run. |
|   ↳ `finish_reason` | string | Yes |  |  | The reason why the sample generation was finished. |
|   ↳ `model` | string | Yes |  |  | The model used for generating the sample. |
|   ↳ `usage` | object (4 properties) | Yes |  |  | Token usage details for the sample. |
|     ↳ `prompt_tokens` | integer | Yes |  |  | The number of prompt tokens used. |
|     ↳ `cached_tokens` | integer | Yes |  |  | The number of tokens retrieved from cache. |
|   ↳ `error` | object (2 properties) | Yes |  |  | An object representing an error response from the Eval API. <br>  |
|   ↳ `temperature` | number | Yes |  |  | The sampling temperature used. |
|   ↳ `max_completion_tokens` | integer | Yes |  |  | The maximum number of tokens allowed for completion. |
|   ↳ `top_p` | number | Yes |  |  | The top_p value used for sampling. |
|   ↳ `seed` | integer | Yes |  |  | The seed used for generating the sample. |


### Items in `input` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `role` | string | Yes |  |  | The role of the message sender (e.g., system, user, developer). |
| `content` | string | Yes |  |  | The content of the message. |


### Items in `output` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `role` | string | No |  |  | The role of the message (e.g. "system", "assistant", "user"). |
| `content` | string | No |  |  | The content of the message. |


### Items in `results` array

Each item is of type `object (map of object)` - A result object.


## Property Details

### `object` (required)

The type of the object. Always "eval.run.output_item".

**Type**: string

**Allowed values**: `eval.run.output_item`

### `id` (required)

Unique identifier for the evaluation run output item.

**Type**: string

### `run_id` (required)

The identifier of the evaluation run associated with this output item.

**Type**: string

### `eval_id` (required)

The identifier of the evaluation group.

**Type**: string

### `created_at` (required)

Unix timestamp (in seconds) when the evaluation run was created.

**Type**: integer

### `status` (required)

The status of the evaluation run.

**Type**: string

### `datasource_item_id` (required)

The identifier for the data source item.

**Type**: integer

### `datasource_item` (required)

Details of the input data source item.

**Type**: object (map of object)

### `results` (required)

A list of results from the evaluation run.

**Type**: array of object (map of object)

### `sample` (required)

A sample containing the input and output of the evaluation run.

**Type**: object (10 properties)

**Nested Properties**:

* `input`, `output`, `finish_reason`, `model`, `usage`, `error`, `temperature`, `max_completion_tokens`, `top_p`, `seed`

## Example

```json
{
  "object": "eval.run.output_item",
  "id": "outputitem_67abd55eb6548190bb580745d5644a33",
  "run_id": "evalrun_67abd54d60ec8190832b46859da808f7",
  "eval_id": "eval_67abd54d9b0081909a86353f6fb9317a",
  "created_at": 1739314509,
  "status": "pass",
  "datasource_item_id": 137,
  "datasource_item": {
      "teacher": "To grade essays, I only check for style, content, and grammar.",
      "student": "I am a student who is trying to write the best essay."
  },
  "results": [
    {
      "name": "String Check Grader",
      "type": "string-check-grader",
      "score": 1.0,
      "passed": true,
    }
  ],
  "sample": {
    "input": [
      {
        "role": "system",
        "content": "You are an evaluator bot..."
      },
      {
        "role": "user",
        "content": "You are assessing..."
      }
    ],
    "output": [
      {
        "role": "assistant",
        "content": "The rubric is not clear nor concise."
      }
    ],
    "finish_reason": "stop",
    "model": "gpt-4o-2024-08-06",
    "usage": {
      "total_tokens": 521,
      "completion_tokens": 2,
      "prompt_tokens": 519,
      "cached_tokens": 0
    },
    "error": null,
    "temperature": 1.0,
    "max_completion_tokens": 2048,
    "top_p": 1.0,
    "seed": 42
  }
}

```

