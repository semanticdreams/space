# error

Emitted when an error occurs.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `error` | The type of the event. Always `error`. <br>  |
| `code` | string | Yes |  |  | The error code. <br>  |
| `message` | string | Yes |  |  | The error message. <br>  |
| `param` | string | Yes |  |  | The error parameter. <br>  |

## Property Details

### `type` (required)

The type of the event. Always `error`.


**Type**: string

**Allowed values**: `error`

### `code` (required)

The error code.


**Type**: string

**Nullable**: Yes

### `message` (required)

The error message.


**Type**: string

### `param` (required)

The error parameter.


**Type**: string

**Nullable**: Yes

## Example

```json
{
  "type": "error",
  "code": "ERR_SOMETHING",
  "message": "Something went wrong",
  "param": null
}

```

