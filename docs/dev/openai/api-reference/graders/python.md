# Python Grader

A PythonGrader object that runs a python script on the input.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `python` | The object type, which is always `python`. |
| `name` | string | Yes |  |  | The name of the grader. |
| `source` | string | Yes |  |  | The source code of the python script. |
| `image_tag` | string | No |  |  | The image tag to use for the python script. |

## Property Details

### `type` (required)

The object type, which is always `python`.

**Type**: string

**Allowed values**: `python`

### `name` (required)

The name of the grader.

**Type**: string

### `source` (required)

The source code of the python script.

**Type**: string

### `image_tag`

The image tag to use for the python script.

**Type**: string

## Example

```json
{
  "type": "python",
  "name": "Example python grader",
  "image_tag": "2025-05-08",
  "source": """
def grade(sample: dict, item: dict) -> float:
    \"""
    Returns 1.0 if `output_text` equals `label`, otherwise 0.0.
    \"""
    output = sample.get("output_text")
    label = item.get("label")
    return 1.0 if output == label else 0.0
""",
}

```

