# Label Model Grader

A LabelModelGrader object which uses a model to assign labels to each item
in the evaluation.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `label_model` | The object type, which is always `label_model`. |
| `name` | string | Yes |  |  | The name of the grader. |
| `model` | string | Yes |  |  | The model to use for the evaluation. Must support structured outputs. |
| `input` | array of object (3 properties) | Yes |  |  |  |
| `labels` | array of string | Yes |  |  | The labels to assign to each item in the evaluation. |
| `passing_labels` | array of string | Yes |  |  | The labels that indicate a passing result. Must be a subset of labels. |


### Items in `input` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `role` | string | Yes |  | `user`, `assistant`, `system`, `developer` | The role of the message input. One of `user`, `assistant`, `system`, or <br> `developer`. <br>  |
| `content` | oneOf: string | object (2 properties) | object (2 properties) | Yes |  |  | Text inputs to the model - can contain template strings. <br>  |
| `type` | string | No |  | `message` | The type of the message input. Always `message`. <br>  |

## Property Details

### `type` (required)

The object type, which is always `label_model`.

**Type**: string

**Allowed values**: `label_model`

### `name` (required)

The name of the grader.

**Type**: string

### `model` (required)

The model to use for the evaluation. Must support structured outputs.

**Type**: string

### `input` (required)

**Type**: array of object (3 properties)

### `labels` (required)

The labels to assign to each item in the evaluation.

**Type**: array of string

### `passing_labels` (required)

The labels that indicate a passing result. Must be a subset of labels.

**Type**: array of string

## Example

```json
{
  "name": "First label grader",
  "type": "label_model",
  "model": "gpt-4o-2024-08-06",
  "input": [
    {
      "type": "message",
      "role": "system",
      "content": {
        "type": "input_text",
        "text": "Classify the sentiment of the following statement as one of positive, neutral, or negative"
      }
    },
    {
      "type": "message",
      "role": "user",
      "content": {
        "type": "input_text",
        "text": "Statement: {{item.response}}"
      }
    }
  ],
  "passing_labels": [
    "positive"
  ],
  "labels": [
    "positive",
    "neutral",
    "negative"
  ]
}

```

