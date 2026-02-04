# error

Returned when an error occurs, which could be a client problem or a server 
problem. Most errors are recoverable and the session will stay open, we 
recommend to implementors to monitor and log error messages by default.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `error` | The event type, must be `error`. |
| `error` | object (5 properties) | Yes |  |  | Details of the error. |
|   ↳ `message` | string | Yes |  |  | A human-readable error message. |
|   ↳ `param` | string | No |  |  | Parameter related to the error, if any. |
|   ↳ `event_id` | string | No |  |  | The event_id of the client event that caused the error, if applicable. <br>  |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `error`.

**Type**: string

**Allowed values**: `error`

### `error` (required)

Details of the error.

**Type**: object (5 properties)

**Nested Properties**:

* `type`, `code`, `message`, `param`, `event_id`

## Example

```json
{
    "event_id": "event_890",
    "type": "error",
    "error": {
        "type": "invalid_request_error",
        "code": "invalid_event",
        "message": "The 'type' field is missing.",
        "param": null,
        "event_id": "event_567"
    }
}

```

