# input_audio_buffer.cleared

Returned when the input audio buffer is cleared by the client with a 
`input_audio_buffer.clear` event.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `input_audio_buffer.cleared` | The event type, must be `input_audio_buffer.cleared`. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `input_audio_buffer.cleared`.

**Type**: string

**Allowed values**: `input_audio_buffer.cleared`

## Example

```json
{
    "event_id": "event_1314",
    "type": "input_audio_buffer.cleared"
}

```

