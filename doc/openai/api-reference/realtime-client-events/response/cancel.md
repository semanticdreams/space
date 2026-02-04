# response.cancel

Send this event to cancel an in-progress response. The server will respond 
with a `response.cancelled` event or an error if there is no response to 
cancel.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | No |  |  | Optional client-generated ID used to identify this event. |
| `type` | string | Yes |  | `response.cancel` | The event type, must be `response.cancel`. |
| `response_id` | string | No |  |  | A specific response ID to cancel - if not provided, will cancel an  <br> in-progress response in the default conversation. <br>  |

## Property Details

### `event_id`

Optional client-generated ID used to identify this event.

**Type**: string

### `type` (required)

The event type, must be `response.cancel`.

**Type**: string

**Allowed values**: `response.cancel`

### `response_id`

A specific response ID to cancel - if not provided, will cancel an 
in-progress response in the default conversation.


**Type**: string

## Example

```json
{
    "event_id": "event_567",
    "type": "response.cancel"
}

```

