# Run grader

`POST` `/fine_tuning/alpha/graders/run`

Run a grader.


## Request Body

### Content Type: `application/json`

### RunGraderRequest

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `grader` | object | Yes |  |  | The grader used for the fine-tuning job. |
| `reference_answer` | oneOf: string | object | array | number | Yes |  |  | The reference answer for the evaluation. |
| `model_sample` | string | Yes |  |  | The model sample to be evaluated. |
## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (4 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `reward` | number | Yes |  |  |  |
| `metadata` | object (7 properties) | Yes |  |  |  |
|   ↳ `errors` | object (14 properties) | Yes |  |  |  |
|     ↳ `truncated_observation_error` | boolean | Yes |  |  |  |
|     ↳ `unresponsive_reward_error` | boolean | Yes |  |  |  |
|     ↳ `invalid_variable_error` | boolean | Yes |  |  |  |
|     ↳ `other_error` | boolean | Yes |  |  |  |
|     ↳ `python_grader_server_error` | boolean | Yes |  |  |  |
|     ↳ `python_grader_server_error_type` | string,null | Yes |  |  |  |
|     ↳ `python_grader_runtime_error` | boolean | Yes |  |  |  |
|     ↳ `python_grader_runtime_error_details` | string,null | Yes |  |  |  |
|     ↳ `model_grader_server_error` | boolean | Yes |  |  |  |
|     ↳ `model_grader_refusal_error` | boolean | Yes |  |  |  |
|     ↳ `model_grader_parse_error` | boolean | Yes |  |  |  |
|     ↳ `model_grader_server_error_details` | string,null | Yes |  |  |  |
|   ↳ `execution_time` | number | Yes |  |  |  |
|   ↳ `scores` | object (map of unknown) | Yes |  |  |  |
|   ↳   ↳ (additional properties) | unknown | - | - | - | Additional properties of this object |
|   ↳ `token_usage` | integer,null | Yes |  |  |  |
|   ↳ `sampled_model_name` | string,null | Yes |  |  |  |
| `sub_rewards` | object (map of unknown) | Yes |  |  |  |
|   ↳ (additional properties) | unknown | - | - | - | Additional properties of this object |
| `model_grader_token_usage_per_model` | object (map of unknown) | Yes |  |  |  |
|   ↳ (additional properties) | unknown | - | - | - | Additional properties of this object |
## Examples

### Request Examples

#### curl
```bash
curl -X POST https://api.openai.com/v1/fine_tuning/alpha/graders/run \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "grader": {
      "type": "score_model",
      "name": "Example score model grader",
      "input": [
        {
          "role": "user",
          "content": "Score how close the reference answer is to the model answer. Score 1.0 if they are the same and 0.0 if they are different. Return just a floating point score\n\nReference answer: {{item.reference_answer}}\n\nModel answer: {{sample.output_text}}"
        }
      ],
      "model": "gpt-4o-2024-08-06",
      "sampling_params": {
        "temperature": 1,
        "top_p": 1,
        "seed": 42
      }
    },
    "reference_answer": "fuzzy wuzzy was a bear",
    "model_sample": "fuzzy wuzzy was a bear"
  }'

```

### Response Example

```json
{
  "reward": 1.0,
  "metadata": {
    "name": "Example score model grader",
    "type": "score_model",
    "errors": {
      "formula_parse_error": false,
      "sample_parse_error": false,
      "truncated_observation_error": false,
      "unresponsive_reward_error": false,
      "invalid_variable_error": false,
      "other_error": false,
      "python_grader_server_error": false,
      "python_grader_server_error_type": null,
      "python_grader_runtime_error": false,
      "python_grader_runtime_error_details": null,
      "model_grader_server_error": false,
      "model_grader_refusal_error": false,
      "model_grader_parse_error": false,
      "model_grader_server_error_details": null
    },
    "execution_time": 4.365238428115845,
    "scores": {},
    "token_usage": {
      "prompt_tokens": 190,
      "total_tokens": 324,
      "completion_tokens": 134,
      "cached_tokens": 0
    },
    "sampled_model_name": "gpt-4o-2024-08-06"
  },
  "sub_rewards": {},
  "model_grader_token_usage_per_model": {
    "gpt-4o-2024-08-06": {
      "prompt_tokens": 190,
      "total_tokens": 324,
      "completion_tokens": 134,
      "cached_tokens": 0
    }
  }
}

```

