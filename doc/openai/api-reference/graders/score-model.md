# Score Model Grader

A ScoreModelGrader object that uses a model to assign a score to the input.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `score_model` | The object type, which is always `score_model`. |
| `name` | string | Yes |  |  | The name of the grader. |
| `model` | string | Yes |  |  | The model to use for the evaluation. |
| `sampling_params` | object | No |  |  | The sampling parameters for the model. |
| `input` | array of object (3 properties) | Yes |  |  | The input text. This may include template strings. |
| `range` | array of number | No |  |  | The range of the score. Defaults to `[0, 1]`. |


### Items in `input` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `role` | string | Yes |  | `user`, `assistant`, `system`, `developer` | The role of the message input. One of `user`, `assistant`, `system`, or <br> `developer`. <br>  |
| `content` | oneOf: string | object (2 properties) | object (2 properties) | Yes |  |  | Text inputs to the model - can contain template strings. <br>  |
| `type` | string | No |  | `message` | The type of the message input. Always `message`. <br>  |

## Property Details

### `type` (required)

The object type, which is always `score_model`.

**Type**: string

**Allowed values**: `score_model`

### `name` (required)

The name of the grader.

**Type**: string

### `model` (required)

The model to use for the evaluation.

**Type**: string

### `sampling_params`

The sampling parameters for the model.

**Type**: object

### `input` (required)

The input text. This may include template strings.

**Type**: array of object (3 properties)

### `range`

The range of the score. Defaults to `[0, 1]`.

**Type**: array of number

## Example

```json
{
    "type": "score_model",
    "name": "Example score model grader",
    "input": [
        {
            "role": "user",
            "content": (
                "Score how close the reference answer is to the model answer. Score 1.0 if they are the same and 0.0 if they are different."
                " Return just a floating point score\n\n"
                " Reference answer: {{item.label}}\n\n"
                " Model answer: {{sample.output_text}}"
            ),
        }
    ],
    "model": "gpt-4o-2024-08-06",
    "sampling_params": {
        "temperature": 1,
        "top_p": 1,
        "seed": 42,
    },
}

```

