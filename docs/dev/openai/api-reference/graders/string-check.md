# String Check Grader

A StringCheckGrader object that performs a string comparison between input and reference using a specified operation.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `string_check` | The object type, which is always `string_check`. |
| `name` | string | Yes |  |  | The name of the grader. |
| `input` | string | Yes |  |  | The input text. This may include template strings. |
| `reference` | string | Yes |  |  | The reference text. This may include template strings. |
| `operation` | string | Yes |  | `eq`, `ne`, `like`, `ilike` | The string check operation to perform. One of `eq`, `ne`, `like`, or `ilike`. |

## Property Details

### `type` (required)

The object type, which is always `string_check`.

**Type**: string

**Allowed values**: `string_check`

### `name` (required)

The name of the grader.

**Type**: string

### `input` (required)

The input text. This may include template strings.

**Type**: string

### `reference` (required)

The reference text. This may include template strings.

**Type**: string

### `operation` (required)

The string check operation to perform. One of `eq`, `ne`, `like`, or `ilike`.

**Type**: string

**Allowed values**: `eq`, `ne`, `like`, `ilike`

## Example

```json
{
  "type": "string_check",
  "name": "Example string check grader",
  "input": "{{sample.output_text}}",
  "reference": "{{item.label}}",
  "operation": "eq"
}

```

