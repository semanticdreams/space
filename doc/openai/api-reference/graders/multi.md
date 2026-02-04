# Multi Grader

A MultiGrader object combines the output of multiple graders to produce a single score.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes | `multi` | `multi` | The object type, which is always `multi`. |
| `name` | string | Yes |  |  | The name of the grader. |
| `graders` | object (map of object) | Yes |  |  |  |
|   ↳ (additional properties) | object | - | - | - | Additional properties of this object |
| `calculate_output` | string | Yes |  |  | A formula to calculate the output based on grader results. |

## Property Details

### `type` (required)

The object type, which is always `multi`.

**Type**: string

**Allowed values**: `multi`

### `name` (required)

The name of the grader.

**Type**: string

### `graders` (required)

**Type**: object (map of object)

### `calculate_output` (required)

A formula to calculate the output based on grader results.

**Type**: string

## Example

```json
{
  "type": "multi",
  "name": "example multi grader",
  "graders": [
    {
      "type": "text_similarity",
      "name": "example text similarity grader",
      "input": "The graded text",
      "reference": "The reference text",
      "evaluation_metric": "fuzzy_match"
    },
    {
      "type": "string_check",
      "name": "Example string check grader",
      "input": "{{sample.output_text}}",
      "reference": "{{item.label}}",
      "operation": "eq"
    }
  ],
  "calculate_output": "0.5 * text_similarity_score +  0.5 * string_check_score)"
}

```

